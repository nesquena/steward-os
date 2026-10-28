# frozen_string_literal: true

require 'yaml'

# Enforces the fail-closed invariants that setup/config.template.yaml,
# docs/reference/security-spine.md #6, and skills/issue-capture/SKILL.md state in
# prose. Checks the statically decidable subset only — writability, reachability,
# and the privacy of destinations outside the repo stay with the runtime preflight.
#
# Split into a pure checker (ConfigContract.check — parsed hashes in, violations
# out) and an Extract module that reads the repo, mirroring lib/skills_contract.rb.
module ConfigContract
  Violation = Struct.new(:severity, :rule, :key, :message, keyword_init: true) do
    SYMBOL = { error: 'x', warning: '!', info: '·' }.freeze

    def to_line
      "  #{SYMBOL.fetch(severity)} #{key} — #{message}"
    end
  end

  # Job schedule keys alternate: a job needs exactly one. Exempt from the set
  # diff so job_schedule_alternation can check them per-job instead.
  SCHEDULE_KEYS = %w[scheduled_jobs.jobs[].every scheduled_jobs.jobs[].cron].freeze

  BOOLEAN_KEYS = %w[
    issue_capture.enabled
    community.chat.monitor
    secrets.execute_contributor_code
    secrets.sandbox_available
  ].freeze

  STRING_KEYS = %w[
    issue_capture.capture_marker
    issue_capture.queue_path
    issue_capture.ledger_path
    issue_capture.checkpoint_path
    community.chat.platform
    community.chat.capture_reaction
    security.security_contact
    scheduled_jobs.outputs.index_path
    scheduled_jobs.outputs.digest_to
    scheduled_jobs.outputs.alarms_to
  ].freeze

  NON_NEGATIVE_INT_KEYS = %w[
    issue_capture.max_per_run
    issue_capture.max_public_files_per_run
  ].freeze

  # Leaves the template declares as an open (empty) list that nonetheless carries
  # a type invariant: each element must be a non-blank string. The shape phase
  # lets a populated list satisfy the empty template leaf, but nothing there
  # checks the element type — so a hash, a scalar, or a blank/mixed array would
  # otherwise ride through and silently drop the surface-detection signal class.
  ARRAY_OF_NON_BLANK_STRING_KEYS = %w[
    security.security_sensitive_surfaces
  ].freeze

  VISIBILITIES = %w[public private].freeze

  # Every semantic rule this phase can emit. Task 6's meta-test asserts each has
  # a red fixture — keep in sync when adding a rule.
  SEMANTIC_RULES = %i[
    alarms_to_required
    alarms_to_independent
    capture_state_paths_required
    state_paths_not_public
    pull_index_required
    index_not_public
    marker_needs_watchdog
    reaction_needs_watchdog
    chat_needs_capture_core
    chat_needs_platform
    public_files_need_watchdog
    sandbox_required
    job_name_unique
    enabled_job_needs_skill
    job_flag_agree
  ].freeze

  # Each template job and the skill that runs it, or nil where none ships yet.
  # JobSkillsMapTest keeps this in step with the template and skills/.
  JOB_SKILLS = {
    'scoreboard-refresh' => 'triage-scoreboard',
    'chat-monitor' => nil,
    'issue-capture' => 'issue-capture',
    'mentions-sweep' => nil,
    'announcements' => 'release-announce',
    'label-sync' => 'label-sync',
    'issue-autoclose' => 'issue-autoclose',
    'action-watchdog' => 'action-watchdog',
    'fleet-heartbeat' => nil
  }.freeze

  # Jobs whose enabled run needs a feature flag on: job name => flag path.
  JOB_FLAGS = {
    'issue-capture' => 'issue_capture.enabled',
    'chat-monitor' => 'community.chat.monitor'
  }.freeze

  # Every rule ParseRules can emit. The meta-test reads this list and
  # SEMANTIC_RULES, so keep it in sync when adding a parse rule.
  PARSE_RULES = %i[
    multiple_documents
    duplicate_key
    merge_key
    explicit_tag
    ambiguous_scalar
  ].freeze

  CAPTURE_STATE_PATHS = %w[queue_path ledger_path checkpoint_path].freeze

  # Pure. Given the parsed config and the parsed template, return violations.
  #
  # Three ordered phases. Phase 3's reads all assume a key exists at the right
  # path with the right type, so a shape or type error suppresses it — that
  # ordering is the fail-closed mechanism, not an optimization.
  def self.check(config:, template:)
    unless config.is_a?(Hash) && !config.empty?
      # Nothing downstream can run, so say so — every suppressing error
      # announces the suppression, this one included.
      return [err(:not_a_mapping, '(document)', 'config is empty or its top level is not a mapping'),
              phases_skipped]
    end

    violations = shape_violations(config, template)

    unless violations.any? { |v| v.severity == :error }
      violations.concat(type_violations(config))
    end

    # `phases_skipped` means "phase 3 never ran", so decide that BEFORE phase 3
    # appends anything. Testing for errors afterwards would tell an adopter
    # whose only fault is semantic that the semantic invariants were not
    # evaluated — false, and in a fail-closed lint actively misleading: they
    # cannot tell "unvetted, could hide more" from "vetted, here is the fault".
    ran_semantics = violations.none? { |v| v.severity == :error }
    violations.concat(semantic_violations(config)) if ran_semantics
    violations << phases_skipped unless ran_semantics

    violations
  end

  # Read a config file and check it. A parse violation means the hash is not
  # the file, so every phase is skipped and said to be.
  def self.check_file(path, template:)
    config, parse_violations = Extract.read(path)
    return parse_violations + [phases_skipped] unless parse_violations.empty?

    check(config: config, template: template)
  end

  def self.phases_skipped
    Violation.new(severity: :info, rule: :phases_skipped, key: '(document)',
                  message: 'semantic invariants NOT evaluated — fix the errors above and re-run')
  end

  # `leaf` sits strictly beneath `ancestor` in the path namespace.
  def self.strict_descendant_of?(leaf, ancestor)
    leaf.start_with?("#{ancestor}.") || leaf.start_with?("#{ancestor}[")
  end

  # A path is satisfied by a leaf that equals it or descends from it. This is
  # the template-empty/config-populated direction: `sources: []` in the
  # template accepts `sources: [...]` in the config. The opposite direction is
  # handled in shape_violations, gated on genuine emptiness.
  def self.covered?(path, leaves)
    leaves.include?(path) || leaves.any? { |l| strict_descendant_of?(l, path) }
  end

  def self.shape_violations(config, template)
    cfg_leaves = Extract.key_paths(config).uniq
    tpl_leaves = Extract.key_paths(template).uniq
    cfg_empty = Extract.empty_collection_paths(config).uniq
    violations = []

    (cfg_leaves - tpl_leaves).sort.each do |path|
      next if SCHEDULE_KEYS.include?(path)
      # `path` plays the leaves role here, `t` the path role: this asks whether
      # `path` sits at or below some template leaf, the mirror image of
      # covered?'s documented "template-empty/config-populated" direction above.
      next if tpl_leaves.any? { |t| covered?(t, [path]) }
      tpl_nests_here = tpl_leaves.any? { |t| strict_descendant_of?(t, path) }
      # unknown-key loop — an empty collection here stands in for whatever the
      # template puts under it; the collection root is not an unknown key.
      next if cfg_empty.include?(path) && tpl_nests_here

      message = if tpl_nests_here
                  'setup/config.template.yaml nests keys under this one — expected a mapping, not a scalar'
                else
                  'not a key in setup/config.template.yaml — check the spelling'
                end

      violations << err(:unknown_key, path, message)
    end

    (tpl_leaves - cfg_leaves).sort.each do |path|
      next if SCHEDULE_KEYS.include?(path)
      next if covered?(path, cfg_leaves)
      # missing-key loop — ...and it accounts for the keys the template puts
      # beneath it. Gated on a genuinely empty [] or {}: a nil or scalar
      # ancestor keeps reporting, or this skip becomes a fail-open hole over
      # the whole subtree.
      next if cfg_empty.any? { |c| strict_descendant_of?(path, c) }

      violations << err(:missing_key, path, 'required by setup/config.template.yaml but absent here')
    end

    violations + job_schedule_violations(config)
  end

  def self.job_schedule_violations(config)
    violations_for_each(config, 'scheduled_jobs', 'jobs') do |job, i|
      set = %w[every cron].count { |k| job.key?(k) }
      name = job['name'].is_a?(String) ? job['name'] : "index #{i}"

      if set != 1
        next [err(:job_schedule_alternation, "scheduled_jobs.jobs[#{i}]",
                  "job '#{name}' must set exactly one of every: or cron: (found #{set})")]
      end

      # Exactly one key is present — but a present value that is not a non-blank
      # string (`cron: null`, `every: ""`, `every: 3600`, an NBSP-only string) is
      # not a schedule. An enabled-but-unschedulable job would otherwise satisfy
      # every watchdog-dependent rule while never running.
      unless schedule_valid?(job)
        actual = job['every'].nil? ? job['cron'] : job['every']
        next [err(:job_schedule_blank, "scheduled_jobs.jobs[#{i}]",
                  "job '#{name}' sets every: or cron: but its value is not a non-blank string " \
                  "(got #{actual.inspect}) — that is not a schedule")]
      end

      []
    end
  end

  # A job carries a usable schedule when exactly one of every:/cron: is present
  # AND that one's value is a non-blank string. Used by both the schedule lint
  # and watchdog_enabled? so an unschedulable watchdog can't satisfy the
  # watchdog-dependent rules.
  def self.schedule_valid?(job)
    return false unless job.is_a?(Hash)
    return false unless %w[every cron].count { |k| job.key?(k) } == 1

    value = job['every'].nil? ? job['cron'] : job['every']
    value.is_a?(String) && !blank?(value)
  end

  # Dotted-path read for non-list paths. List members are walked explicitly.
  def self.fetch_path(hash, dotted)
    dotted.split('.').reduce(hash) do |node, key|
      return nil unless node.is_a?(Hash)

      node[key]
    end
  end

  # Yield each Hash element of the array at `path`, with its index, and
  # concatenate the violation arrays the block returns. The block always
  # returns an Array — `[]` means "nothing wrong with this element".
  #
  # Three call sites walk a list of hashes this way (job schedules, job types,
  # repository visibility). They share this instead of each rewriting the
  # walk. Walks the path by hand rather than with `dig`: dig raises TypeError
  # when an intermediate is a scalar, and a malformed `scheduled_jobs: yes`
  # must be reported by the shape or type phase, not crash the lint.
  def self.violations_for_each(config, *path)
    node = path.reduce(config) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
    return [] unless node.is_a?(Array)

    node.each_with_index.flat_map do |item, index|
      item.is_a?(Hash) ? yield(item, index) : []
    end
  end

  def self.type_violations(config)
    violations = []

    BOOLEAN_KEYS.each do |path|
      value = fetch_path(config, path)
      next if [true, false].include?(value)

      violations << type_error(:type_boolean, path, value, 'true or false')
    end

    STRING_KEYS.each do |path|
      value = fetch_path(config, path)
      next if value.is_a?(String)

      violations << type_error(:type_string, path, value, 'a string (blank disables)')
    end

    NON_NEGATIVE_INT_KEYS.each do |path|
      value = fetch_path(config, path)
      next if value.is_a?(Integer) && !value.negative?

      violations << type_error(:type_non_negative_integer, path, value, 'an integer >= 0')
    end

    ARRAY_OF_NON_BLANK_STRING_KEYS.each do |path|
      value = fetch_path(config, path)
      # An empty [] is a valid "no surfaces declared". Genuine absence is a
      # phase-1 missing_key error that suppresses this whole phase, so reaching
      # here with nil means the key is present-and-null (or a `security: {}`
      # stand-in whose siblings also error) — a malformed security contract that
      # must fail closed, exactly like every other present-null invariant key.
      next if value.is_a?(Array) && value.all? { |e| e.is_a?(String) && !blank?(e) }

      violations << type_error(:type_string_array, path, value, 'an array of non-blank strings')
    end

    violations + repository_violations(config) + job_type_violations(config)
  end

  def self.type_error(rule, key, value, expected)
    Violation.new(severity: :error, rule: rule, key: key,
                  message: "expected #{expected}, got #{value.class} (#{value.inspect})")
  end

  def self.err(rule, key, message)
    Violation.new(severity: :error, rule: rule, key: key, message: message)
  end

  def self.repository_violations(config)
    violations_for_each(config, 'repositories') do |repo, i|
      value = repo['visibility']
      next [] if VISIBILITIES.include?(value)

      [err(:type_enum, "repositories[#{i}].visibility",
           "expected one of #{VISIBILITIES.join(', ')}, got #{value.inspect}")]
    end
  end

  def self.job_type_violations(config)
    violations_for_each(config, 'scheduled_jobs', 'jobs') do |job, i|
      violations = []
      unless job['name'].is_a?(String)
        violations << type_error(:type_string, "scheduled_jobs.jobs[#{i}].name", job['name'], 'a string')
      end
      unless [true, false].include?(job['enabled'])
        violations << type_error(:type_boolean, "scheduled_jobs.jobs[#{i}].enabled", job['enabled'],
                                 'true or false')
      end
      violations
    end
  end

  # Blank = nil, or a string that is empty or ALL whitespace. Uses a
  # Unicode-aware whitespace class ([[:space:]] matches U+00A0 NBSP and friends,
  # which String#strip does NOT) so a visually-blank value can't masquerade as a
  # real one. This is the single non-blank-string predicate: schedule values,
  # destinations, and string-array elements all route through it so a NBSP-only
  # entry fails closed everywhere, not just where strip happens to catch it.
  def self.blank?(value)
    value.nil? || (value.is_a?(String) && value.match?(/\A[[:space:]]*\z/))
  end

  # Trim leading/trailing whitespace with the SAME Unicode-aware class blank?
  # uses ([[:space:]] catches U+00A0 NBSP etc., which String#strip does not).
  # Used to normalize strings before an equality comparison — e.g. the alarms_to
  # alias check — so an NBSP-padded duplicate can't dodge a route-independence
  # rule the way an ASCII-strip'd comparison would let it.
  def self.unicode_strip(str)
    str.gsub(/\A[[:space:]]+|[[:space:]]+\z/, '')
  end

  # No URI scheme, not absolute, not home-relative, not drive-qualified, and —
  # after normalizing `.`/`..` segments — still inside the repo root. Anything
  # else is outside the repo and routes to the unverifiable warning instead of
  # index_not_public.
  #
  # Backslashes are normalized to `/` FIRST so a Windows-style rooted path
  # (`\srv\x`), a UNC path (`\\host\share\x`), or a mixed-separator path is
  # classified the same as its forward-slash form. Without this the absolute and
  # traversal checks run on the raw string and a backslash-rooted path slips
  # through as repo-relative — the same fail-open double-suppression this method
  # closes for `..`. Any `X:`-prefixed path is a Windows drive reference (rooted
  # or drive-relative) and is treated as outside; nobody writes a repo-relative
  # config path that begins with a drive letter and colon.
  #
  # A `..`-escaped path (`../public-site/vulns.md`) is exactly as undecidable as
  # an absolute path: its privacy can't be settled statically. Classifying it as
  # repo-relative was a fail-open hole — in an all-private declaration it
  # suppressed both index_not_public AND the outside-repo warning. Normalize
  # first, then treat any path that resolves at or above the repo root as
  # outside/unverifiable.
  def self.repo_relative?(path)
    return false if blank?(path)

    normalized = path.tr('\\', '/')
    return false if normalized.include?('://') || normalized.start_with?('/', '~')
    return false if normalized.match?(/\A[A-Za-z]:/)
    return false if escapes_repo_root?(normalized)

    true
  end

  # True when the `.`/`..` segments in a relative path resolve to the repo root
  # itself or anywhere above it — i.e. the path does not stay strictly inside the
  # repo. Pure string normalization (no filesystem access): a leading `..` or a
  # traversal that pops past the root escapes. Backslashes are normalized to `/`
  # so a mixed-separator `..\x` is caught too.
  def self.escapes_repo_root?(path)
    depth = 0
    path.tr('\\', '/').split('/').each do |segment|
      next if segment.empty? || segment == '.'

      if segment == '..'
        depth -= 1
        return true if depth < 0
      else
        depth += 1
      end
    end
    # depth == 0 means it resolved back to the repo root (e.g. `state/../`),
    # which is not a file strictly inside the repo either.
    depth <= 0
  end

  def self.watchdog_enabled?(config)
    jobs = config.dig('scheduled_jobs', 'jobs')
    return false unless jobs.is_a?(Array)

    # An enabled watchdog with no usable schedule never runs, so it does not
    # count as watchdog coverage for the watchdog-dependent semantic rules.
    jobs.any? do |j|
      j.is_a?(Hash) && j['name'] == 'action-watchdog' && j['enabled'] == true && schedule_valid?(j)
    end
  end

  # alarms_to must be an independent fallback. Reject the statically-decidable
  # duplicates: the same string as security_contact, index_path, or any
  # capture-state path. The subtler "different string but same inbox" case is
  # not statically decidable and stays with the runtime preflight. Compared as
  # trimmed strings so trailing whitespace can't dodge the check.
  def self.alarms_to_aliased?(config, outputs)
    target = outputs['alarms_to']
    return false unless target.is_a?(String)

    norm = unicode_strip(target)
    return false if norm.empty?

    others = [config.dig('security', 'security_contact'), outputs['index_path']]
    others += CAPTURE_STATE_PATHS.map { |k| config.dig('issue_capture', k) }
    others.any? { |o| o.is_a?(String) && unicode_strip(o) == norm }
  end

  def self.semantic_violations(config)
    capture = config.dig('issue_capture', 'enabled') == true
    monitor = config.dig('community', 'chat', 'monitor') == true
    marker  = config.dig('issue_capture', 'capture_marker')
    platform = config.dig('community', 'chat', 'platform')
    reaction = config.dig('community', 'chat', 'capture_reaction')
    outputs = config.dig('scheduled_jobs', 'outputs') || {}
    index   = outputs['index_path']
    watchdog = watchdog_enabled?(config)

    violations = []

    if capture
      if blank?(outputs['alarms_to'])
        violations << err(:alarms_to_required, 'scheduled_jobs.outputs.alarms_to',
                          'required when issue_capture.enabled — the divert needs an independent ' \
                          'human route even when security_contact is set (config.template.yaml:130)')
      elsif alarms_to_aliased?(config, outputs)
        violations << err(:alarms_to_independent, 'scheduled_jobs.outputs.alarms_to',
                          'must be an independent human route — it duplicates security_contact, ' \
                          'index_path, or a capture-state path, so the divert has no fallback ' \
                          'distinct from the destination it is meant to back up (config.template.yaml:130)')
      end

      missing = CAPTURE_STATE_PATHS.select { |k| blank?(config.dig('issue_capture', k)) }
      unless missing.empty?
        violations << err(:capture_state_paths_required, 'issue_capture',
                          "issue_capture.enabled requires private #{missing.join(', ')} " \
                          '(issue-capture/SKILL.md:19-21)')
      end

      public_state = CAPTURE_STATE_PATHS.select { |k| repo_relative?(config.dig('issue_capture', k)) }
      if !public_state.empty? && public_repo?(config)
        violations << err(:state_paths_not_public, 'issue_capture',
                          "#{public_state.join(', ')} are repo-relative and this project lists a " \
                          'public repository. Capture state holds the diverted-vulnerability audit ' \
                          'trail and must not be a public surface (config.template.yaml:46-48). Use ' \
                          'an absolute path if it lives in a private repo')
      end

      if blank?(index)
        violations << err(:pull_index_required, 'scheduled_jobs.outputs.index_path',
                          'issue_capture.enabled requires a pull index (issue-capture/SKILL.md:26-27)')
      elsif repo_relative?(index) && public_repo?(config)
        violations << err(:index_not_public, 'scheduled_jobs.outputs.index_path',
                          "'#{index}' is repo-relative and this project lists a public repository. " \
                          'An index that can hold a diverted vulnerability must not be a public ' \
                          'surface (config.template.yaml:124-126). If it lives in a private repo, ' \
                          'use an absolute path to say so')
      end
    end

    # Deliberately NOT gated on issue_capture.enabled: a stale non-blank marker
    # left over from a disabled capture config is still a public marker with
    # no watchdog behind it, and that is exactly what this rule exists to catch.
    unless blank?(marker) || watchdog
      violations << err(:marker_needs_watchdog, 'issue_capture.capture_marker',
                        'a public capture marker requires an enabled action-watchdog job ' \
                        '(config.template.yaml:51)')
    end

    # Gated on platform being set: with platform blank, chat_needs_platform already
    # reports monitoring as disabled, and firing this rule too would tell the
    # adopter two contradictory things about the same run.
    if monitor && !blank?(platform) && !blank?(reaction) && !watchdog
      violations << err(:reaction_needs_watchdog, 'community.chat.capture_reaction',
                        'a public capture reaction requires an enabled action-watchdog job ' \
                        '(issue-capture/SKILL.md:23-25)')
    end

    if monitor && !capture
      violations << err(:chat_needs_capture_core, 'community.chat.monitor',
                        'chat monitoring requires issue_capture.enabled — chat must not implement ' \
                        'a second capture path (config.template.yaml:44)')
    end

    if monitor && blank?(platform)
      violations << err(:chat_needs_platform, 'community.chat.platform',
                        'a blank platform means chat monitoring is disabled, but monitor is true ' \
                        '(config.template.yaml:32)')
    end

    # Deliberately NOT gated on issue_capture.enabled either: a positive bound
    # left set while capture is off still describes an autonomous-filing policy
    # with no watchdog behind it once capture is re-enabled without review.
    files = config.dig('issue_capture', 'max_public_files_per_run')
    if files.is_a?(Integer) && files.positive? && !watchdog
      violations << err(:public_files_need_watchdog, 'issue_capture.max_public_files_per_run',
                        'autonomous public filing requires an enabled action-watchdog ' \
                        '(INFERRED from security-spine.md §5 and the self-test at :152, not a ' \
                        'literal config line)')
    end

    if config.dig('secrets', 'execute_contributor_code') == true &&
       config.dig('secrets', 'sandbox_available') != true
      violations << err(:sandbox_required, 'secrets.execute_contributor_code',
                        'running contributor code requires sandbox_available: true ' \
                        '(config.template.yaml:106)')
    end

    violations + job_violations(config) + unverifiable_warning(config, outputs, index)
  end

  # Runtimes differ on whether `Issue_Capture ` is `issue-capture`, so the job
  # rules assume it is: an exact match would let a near-miss name slip past.
  # Invisible format characters (zero-width space, BOM) are dropped too.
  def self.normalize_job_name(name)
    unicode_strip(name.gsub(/\p{Cf}/, '')).downcase.tr('_', '-')
  end

  def self.job_violations(config)
    first_index = {}
    violations_for_each(config, 'scheduled_jobs', 'jobs') do |job, i|
      next [] unless job['name'].is_a?(String)

      name = normalize_job_name(job['name'])
      found = []
      if first_index.key?(name)
        found << err(:job_name_unique, "scheduled_jobs.jobs[#{i}]",
                     "job '#{job['name']}' repeats the name of job #{first_index[name]}; a " \
                     'scheduler picks one of them, and nothing says which')
      end
      first_index[name] ||= i
      found + enabled_job_violations(config, job, name, i)
    end
  end

  def self.enabled_job_violations(config, job, name, index)
    return [] unless job['enabled'] == true

    found = []
    if job['agent'] == true && JOB_SKILLS.key?(name) && JOB_SKILLS[name].nil?
      found << err(:enabled_job_needs_skill, "scheduled_jobs.jobs[#{index}]",
                   "job '#{job['name']}' has no skill in this repo yet, so nothing shipped " \
                   'bounds the model it runs')
    end
    flag = JOB_FLAGS[name]
    if flag && fetch_path(config, flag) != true
      found << err(:job_flag_agree, "scheduled_jobs.jobs[#{index}]",
                   "job '#{job['name']}' is enabled but #{flag} is not true, so the rules that " \
                   'guard it never run')
    end
    found
  end

  # Fail closed on "no declared repositories". An adopter who declares none
  # has unknown visibility, and unknown is exactly the case index_not_public
  # must resolve pessimistically — the mixed-visibility case already does.
  # Note phase 1's empty-collection allowance deliberately lets `repositories: []`
  # through without a missing-key error, so nothing upstream catches this.
  def self.public_repo?(config)
    repos = config['repositories']
    return true unless repos.is_a?(Array) && repos.any? { |r| r.is_a?(Hash) }

    repos.any? { |r| r.is_a?(Hash) && r['visibility'] == 'public' }
  end

  # One grouped warning, not one per destination: three separate warnings would
  # fire on every correctly-configured adopter and train them to ignore output.
  #
  # "Confirm each" must be literally exhaustive: every destination whose privacy
  # is not statically decidable belongs here. That is the outside-repo index, the
  # digest/alarms channels, a non-sentinel security_contact (the preferred first
  # destination for the scrubbed vuln summary — SKILL.md:22), and any absolute
  # capture-state path (queue/ledger/checkpoint). Repo-relative destinations are
  # decided by index_not_public / state_paths_not_public; blanks by their
  # required-rules; the "github-advisory" sentinel is statically known-private.
  def self.unverifiable_warning(config, outputs, index)
    return [] unless config.dig('issue_capture', 'enabled') == true

    undecidable = 'channel privacy not statically decidable'
    unverifiable = []
    unverifiable << "index_path '#{index}' (outside the repo)" if !blank?(index) && !repo_relative?(index)
    unverifiable << "digest_to '#{outputs['digest_to']}' (#{undecidable})" unless blank?(outputs['digest_to'])
    unverifiable << "alarms_to '#{outputs['alarms_to']}' (#{undecidable})" unless blank?(outputs['alarms_to'])

    security_contact = config.dig('security', 'security_contact')
    if !blank?(security_contact) && security_contact != 'github-advisory'
      unverifiable << "security_contact '#{security_contact}' (#{undecidable})"
    end

    CAPTURE_STATE_PATHS.each do |k|
      value = config.dig('issue_capture', k)
      next if blank?(value) || repo_relative?(value)

      unverifiable << "issue_capture.#{k} '#{value}' (outside the repo)"
    end
    return [] if unverifiable.empty?

    # The leading spaces below line the continuation up under Violation#to_line's
    # own two-space "  x " prefix (see to_line above) so bin/config-lint's
    # per-line output stays visually aligned. Re-indenting or wrapping this
    # message breaks that alignment — Task 5 prints it verbatim.
    [Violation.new(severity: :warning, rule: :destinations_unverifiable, key: 'scheduled_jobs.outputs',
                   message: "#{unverifiable.size} destination(s) could not be verified as private:\n" \
                            "#{unverifiable.map { |u| "      #{u}" }.join("\n")}\n" \
                            '    Confirm each before enabling autonomous capture.')]
  end

  # Rules that read the YAML stream before anything converts it. Each names a
  # construct that lets the parsed hash differ from what a reader of the file
  # sees, so every later phase would vet a config nobody wrote. Inspection
  # only: conversion stays YAML.safe_load on the source text. Never call
  # to_ruby on these nodes; it builds whatever a !ruby/object tag names.
  module ParseRules
    # Resolves a plain key the way the safe loader would (`yes` and `true` both
    # become true), so keys that collide only after resolution are caught.
    KEY_SCANNER = Psych::ScalarScanner.new(Psych::ClassLoader::Restricted.new([], []))

    # Psych matches these words in any case; other readers accept only the
    # spellings below and read the rest as strings, which are truthy. So
    # `enabled: oFF` is off to the lint and on to such a runtime.
    CANONICAL_WORDS = %w[
      true True TRUE false False FALSE yes Yes YES no No NO
      on On ON off Off OFF null Null NULL
    ].freeze
    BOOL_OR_NULL_WORD = /\A(?:true|false|yes|no|on|off|null)\z/i
    # Base-60 numbers (`1:30`): Psych and other readers compute different values.
    SEXAGESIMAL = /\A[-+]?\d[\d_]*(?::[0-5]?\d)+(?:\.\d*)?\z/

    module_function

    def violations(text)
      documents = Psych.parse_stream(text).children
      return [] if documents.empty?
      return [multiple_documents(documents)] if documents.size > 1

      walk(documents.first.root, '')
    end

    def multiple_documents(documents)
      ConfigContract.err(:multiple_documents, '(document)',
                         "#{documents.size} YAML documents, but the lint reads only the first; " \
                         "document 2 starts at line #{documents[1].start_line + 1} " \
                         '(a trailing --- opens a document too)')
    end

    def walk(node, path)
      found = []
      found << explicit_tag(node, path) if node.respond_to?(:tag) && node.tag
      found << ambiguous_scalar(node, path) if ambiguous?(node)

      case node
      when Psych::Nodes::Mapping
        found.concat(mapping(node, path))
      when Psych::Nodes::Sequence
        node.children.each_with_index { |child, i| found.concat(walk(child, "#{path}[#{i}]")) }
      end
      found
    end

    def mapping(node, path)
      found = []
      seen = {}
      node.children.each_slice(2) do |key, value|
        found.concat(walk(key, path))
        label = key.is_a?(Psych::Nodes::Scalar) ? key.value : "[key at line #{key.start_line + 1}]"
        child = path.empty? ? label : "#{path}.#{label}"
        found << merge_key(child) if key.is_a?(Psych::Nodes::Scalar) && key.value == '<<'
        identities = key_identities(key)
        earlier = identities.filter_map { |id| seen[id] }.first
        found << duplicate_key(child, earlier, key) if earlier
        identities.each { |id| seen[id] ||= key }
        found.concat(walk(value, child))
      end
      found
    end

    # A scalar key matches by its text or by what it resolves to; a list or
    # map key matches by its structure.
    def key_identities(key)
      return [[:shape, shape(key)]] unless key.is_a?(Psych::Nodes::Scalar)

      [[:text, key.value], [:resolved, resolve(key)]]
    end

    def shape(node)
      case node
      when Psych::Nodes::Scalar then [:scalar, node.value]
      when Psych::Nodes::Alias then [:alias, node.anchor]
      else [node.class.name, node.children.map { |child| shape(child) }]
      end
    end

    def ambiguous?(node)
      return false unless node.is_a?(Psych::Nodes::Scalar) && node.plain && !node.tag

      value = node.value
      (value.match?(BOOL_OR_NULL_WORD) && !CANONICAL_WORDS.include?(value)) || value.match?(SEXAGESIMAL)
    end

    def resolve(key)
      key.quoted ? key.value : KEY_SCANNER.tokenize(key.value)
    end

    def duplicate_key(path, first, again)
      where = if first.start_line == again.start_line
                "line #{again.start_line + 1}, columns #{first.start_column + 1} and #{again.start_column + 1}"
              else
                "lines #{first.start_line + 1} and #{again.start_line + 1}"
              end
      ConfigContract.err(:duplicate_key, path,
                         "key repeated at #{where}; YAML readers keep different copies, so the " \
                         'lint cannot know which one you meant')
    end

    def merge_key(path)
      ConfigContract.err(:merge_key, path,
                         'a << merge key lets merged values override keys written explicitly, ' \
                         'and readers disagree on which wins; write the keys out')
    end

    def ambiguous_scalar(node, path)
      ConfigContract.err(:ambiguous_scalar, path.empty? ? '(document)' : path,
                         "'#{node.value}' at line #{node.start_line + 1} reads as a different " \
                         'value in other YAML readers; write a lowercase true/false/null, or quote it')
    end

    def explicit_tag(node, path)
      ConfigContract.err(:explicit_tag, path.empty? ? '(document)' : path,
                         "explicit YAML tag #{node.tag} at line #{node.start_line + 1}; readers " \
                         'resolve tags differently, and this config needs none')
    end
  end

  # Repo readers. Each is small and testable against real files.
  module Extract
    # Subtrees whose keys are adopter-defined (path globs, title prefixes, bucket
    # names). Descending would report every adopter's own keys as unknown.
    # Documented cost: a typo inside one of these goes unchecked.
    OPAQUE_SUBTREES = %w[
      labels.area.map
      labels.type.map
      labels.size.buckets
    ].freeze

    module_function

    # Parse a config. Raises a clear error rather than a bare Psych stacktrace.
    def load(path)
      YAML.safe_load(File.read(path)) || {}
    rescue Psych::Exception => e
      raise "could not parse #{path}: #{e.message}"
    end

    # Parse a config and run the parse rules first. Returns [hash, []] for a
    # file the lint can trust, or [nil, violations] when the parsed hash would
    # not be what the file says. Conversion is YAML.safe_load on the text.
    def read(path)
      text = File.read(path)
      violations = ParseRules.violations(text)
      return [nil, violations] unless violations.empty?

      [YAML.safe_load(text) || {}, []]
    rescue Psych::Exception => e
      raise "could not parse #{path}: #{e.message}"
    end

    # Every leaf path paired with its node. key_paths and
    # empty_collection_paths are both views of this one walk.
    def leaves(node, prefix = '')
      return [[prefix, node]] if !prefix.empty? && OPAQUE_SUBTREES.include?(prefix)

      case node
      when Hash
        return [[prefix, node]] if node.empty?

        node.flat_map { |k, v| leaves(v, prefix.empty? ? k.to_s : "#{prefix}.#{k}") }
      when Array
        return [[prefix, node]] if node.empty?

        node.flat_map { |v| leaves(v, "#{prefix}[]") }
      else
        [[prefix, node]]
      end
    end

    # Every leaf key path, dotted, with list elements normalized to `[]` so a
    # one-element template list and a five-element adopter list compare equal.
    # An empty Hash or Array is itself a leaf.
    def key_paths(node, prefix = '')
      leaves(node, prefix).map(&:first)
    end

    # The subset of leaf paths whose node is an empty [] or {}. An empty
    # collection is a leaf that stands in for whatever the other file puts
    # beneath it; nil and scalars deliberately do not qualify.
    def empty_collection_paths(node, prefix = '')
      leaves(node, prefix).filter_map do |path, value|
        path if (value.is_a?(Hash) || value.is_a?(Array)) && value.empty?
      end
    end
  end
end
