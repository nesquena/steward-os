# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/skills_contract'

ROOT = File.expand_path('..', __dir__)

# --- Pure checker: each rule, in isolation, with crafted sets ---
class CheckerTest < Minitest::Test
  def sev(violations, skill)
    v = violations.find { |x| x.skill == skill }
    v&.severity
  end

  def test_referenced_but_missing_and_undeclared_is_error
    v = SkillsContract.check(present: %w[a], referenced_strict: %w[a ghost], indexed: %w[a])
    assert_equal :error, sev(v, 'ghost')
  end

  def test_referenced_but_missing_yet_planned_is_info
    v = SkillsContract.check(present: %w[a], referenced_strict: %w[a ghost], indexed: %w[a],
                             planned: %w[ghost])
    assert_equal :info, sev(v, 'ghost')
    assert_empty v.select { |x| x.severity == :error }
  end

  def test_planned_skill_that_now_exists_is_stale_error
    v = SkillsContract.check(present: %w[a done], referenced_strict: %w[a done], indexed: %w[a done],
                             planned: %w[done])
    assert_equal :error, sev(v, 'done')
    assert_match(/remove it/, v.find { |x| x.skill == 'done' }.message)
  end

  def test_present_but_not_indexed_is_error
    v = SkillsContract.check(present: %w[a b], referenced_strict: %w[a b], indexed: %w[a])
    assert_equal :error, sev(v, 'b')
  end

  def test_indexed_but_absent_is_error
    v = SkillsContract.check(present: %w[a], referenced_strict: %w[a], indexed: %w[a phantom])
    assert_equal :error, sev(v, 'phantom')
  end

  def test_orphan_present_unreferenced_is_warning
    v = SkillsContract.check(present: %w[a lonely], referenced_strict: %w[a], indexed: %w[a lonely])
    assert_equal :warning, sev(v, 'lonely')
  end

  def test_standalone_suppresses_orphan_warning
    v = SkillsContract.check(present: %w[a lonely], referenced_strict: %w[a], indexed: %w[a lonely],
                             standalone: %w[lonely])
    assert_nil sev(v, 'lonely')
  end

  def test_clean_contract_has_no_errors_or_warnings
    v = SkillsContract.check(present: %w[a b], referenced_strict: %w[a b], indexed: %w[a b])
    assert_empty v
  end
end

# --- Extractors against the real repo ---
class ExtractTest < Minitest::Test
  def test_present_skills_are_discovered
    present = SkillsContract::Extract.present_skills(File.join(ROOT, 'skills'))
    assert_includes present, 'release-announce'
    assert_includes present, 'action-watchdog'
    assert_equal present, present.uniq.sort
  end

  def test_indexed_matches_present
    present = SkillsContract::Extract.present_skills(File.join(ROOT, 'skills'))
    indexed = SkillsContract::Extract.indexed_skills(File.join(ROOT, 'skills', 'README.md'))
    assert_equal present, indexed, 'skills/README.md index should list exactly the present skills'
  end

  def test_doc_sections_pick_up_named_skills_without_noise
    names = SkillsContract::Extract.doc_section_skills(Dir.glob(File.join(ROOT, 'docs', '**', '*.md')))
    assert_includes names, 'chat-monitor'
    assert_includes names, 'issue-autoclose'
    assert_includes names, 'contributor-trust'
    refute_includes names, 'skills/', 'a backticked path with a slash is not a skill name'
  end

  def test_leading_skill_takes_only_the_first_backtick
    assert_equal 'chat-monitor',
                 SkillsContract::Extract.leading_skill('- `chat-monitor` — Watcher: dedupe, capture.')
    assert_equal 'issue-triage',
                 SkillsContract::Extract.leading_skill('- `issue-triage` reads the `labels` config key'),
                 'an inline backtick later in the bullet must NOT be treated as a skill'
    assert_nil SkillsContract::Extract.leading_skill('- (Credit handling is woven into `pr-deep-review`.)'),
               'a parenthetical with no leading backtick declares no skill'
    assert_nil SkillsContract::Extract.leading_skill('- `Watcher` classifies reports'),
               'a capitalized token is not a skill name'
    assert_nil SkillsContract::Extract.leading_skill('some prose, not a bullet')
  end

  def test_indexed_handles_path_prefixed_links
    Dir.mktmpdir do |dir|
      readme = File.join(dir, 'README.md')
      File.write(readme, <<~MD)
        | [`bare`](bare/SKILL.md) | x |
        | [`prefixed`](skills/prefixed/SKILL.md) | x |
        | [`dotted`](./dotted/SKILL.md) | x |
        | [unrelated](../docs/foo.md) | x |
      MD
      assert_equal %w[bare dotted prefixed], SkillsContract::Extract.indexed_skills(readme)
    end
  end

  def test_referenced_resolves_job_aliases
    ref = SkillsContract::Extract.referenced_strict(
      doc_paths: Dir.glob(File.join(ROOT, 'docs', '**', '*.md')),
      config_path: File.join(ROOT, 'setup', 'config.template.yaml'),
      job_aliases: { 'scoreboard-refresh' => 'triage-scoreboard', 'announcements' => 'release-announce' }
    )
    assert_includes ref, 'triage-scoreboard', 'scoreboard-refresh job resolves to the skill'
    assert_includes ref, 'label-sync', 'raw job name with no alias is referenced as-is'
    refute_includes ref, 'scoreboard-refresh', 'the aliased job name itself is not a skill'
  end
end

# --- End to end: the real repo passes with the committed policy ---
class RepoContractTest < Minitest::Test
  def test_current_repo_has_no_errors
    policy = YAML.safe_load(File.read(File.join(ROOT, '_data', 'skills.yml'))) || {}
    doc_paths = Dir.glob(File.join(ROOT, 'docs', '**', '*.md'))
    skills_dir = File.join(ROOT, 'skills')
    present = SkillsContract::Extract.present_skills(skills_dir)
    indexed = SkillsContract::Extract.indexed_skills(File.join(skills_dir, 'README.md'))
    referenced = SkillsContract::Extract.referenced_strict(
      doc_paths: doc_paths,
      config_path: File.join(ROOT, 'setup', 'config.template.yaml'),
      job_aliases: policy['job_aliases'] || {}
    )
    v = SkillsContract.check(
      present: present, referenced_strict: referenced, indexed: indexed,
      planned: policy['planned'] || [], standalone: policy['standalone'] || []
    )
    errors = v.select { |x| x.severity == :error }
    assert_empty errors, "unexpected contract errors: #{errors.map(&:to_line).join("\n")}"

    # the remaining known-missing skills are accounted for as planned (info)
    infos = v.select { |x| x.severity == :info }.map(&:skill)
    assert_includes infos, 'chat-monitor'
  end
end

# --- The issue-capture responsibility is complete across config, lifecycle, and watchdog ---
class IssueCaptureContractTest < Minitest::Test
  REQUIRED_CONFIG_KEYS = %w[
    enabled sources queue_path ledger_path checkpoint_path max_per_run
    max_public_files_per_run capture_marker
  ].freeze

  def test_template_and_dogfood_config_keep_the_capture_contract
    template = YAML.safe_load(File.read(File.join(ROOT, 'setup', 'config.template.yaml')))
    dogfood = YAML.safe_load(File.read(File.join(ROOT, 'setup', 'config.yaml')))

    assert_equal template.keys.sort, dogfood.keys.sort
    assert_equal REQUIRED_CONFIG_KEYS.sort, template.fetch('issue_capture').keys.sort
    assert_equal template.fetch('issue_capture').keys.sort, dogfood.fetch('issue_capture').keys.sort
  end

  def test_issue_capture_is_runnable_wired_and_not_still_planned
    template = YAML.safe_load(File.read(File.join(ROOT, 'setup', 'config.template.yaml')))
    jobs = template.fetch('scheduled_jobs').fetch('jobs').to_h { |job| [job.fetch('name'), job] }
    policy = YAML.safe_load(File.read(File.join(ROOT, '_data', 'skills.yml')))
    capture = File.read(File.join(ROOT, 'skills', 'issue-capture', 'SKILL.md'))

    assert_includes jobs, 'issue-capture'
    assert_includes jobs, 'action-watchdog'
    refute_includes policy.fetch('planned'), 'issue-capture'
    assert File.file?(File.join(ROOT, 'skills', 'issue-capture', 'SKILL.md'))
    assert_includes capture, 'plus a writable pull index'
    assert_match(/Require `alarms_to` as an\s+independent error route/, capture)
    assert_match(/configured for an enabled source without an enabled `action-watchdog`/, capture)
    assert_includes capture, 'alarm and fail before scanning'
    assert_includes capture, "marker configuration to blank before the run"
    refute_includes capture, 'private capture may continue'
  end

  def test_capture_has_one_owner_and_a_complete_transition_contract
    capture = File.read(File.join(ROOT, 'skills', 'issue-capture', 'SKILL.md'))
    watchdog = File.read(File.join(ROOT, 'skills', 'action-watchdog', 'SKILL.md'))
    triage = File.read(File.join(ROOT, 'skills', 'issue-triage', 'SKILL.md'))
    community = File.read(File.join(ROOT, 'docs', 'lifecycle', 'community.md'))

    assert_operator capture.index('**Vulnerability divert'), :<, capture.index('**Classify and tier')
    assert_operator capture.index('private delivery succeeds'), :<, capture.index('terminal `diverted` event')
    assert_includes capture, 'adapter + stable source item id + target repository'
    assert_includes capture, 'terminal `noise` event'
    assert_includes capture, 'terminal `duplicate` event'
    assert_includes capture, '`community.chat.capture_reaction`'
    assert_includes capture, 'atomically upsert a privacy-safe index summary keyed only by the opaque queue id'
    assert_includes capture, 'Keep the capture key and private source reference out of every'
    assert_operator capture.index('Append `indexed`'), :<, capture.index('terminal `captured` event')
    assert_includes watchdog, '[`issue-capture`](../issue-capture/SKILL.md)'
    assert_includes watchdog, '**Autonomous issue files**'
    assert_includes community, '`chat-monitor` only reads'
    assert_includes community, '`issue-capture` owns the untrusted-data guard'
    assert_includes community, 'Chat monitoring stays off until the shared capture core'
    refute_includes triage, '**Capture-dedupe.**', 'pre-tracker capture has one procedural owner'
  end
end

# --- Injection guard: the block every untrusted-reading skill opens with ---
class GuardCheckerTest < Minitest::Test
  def guards(**over)
    base = {
      present: %w[a b], guarded: %w[a], exempt: { 'b' => 'no-model' }, guard_text: 'G.',
      blocks: { 'a' => SkillsContract.normalize_guard("G. #{SkillsContract::GUARD_LINK_LINE}") },
      spine_quote: 'G.', no_llm: %w[b], job_agents: {}
    }
    SkillsContract.check_guards(**base.merge(over))
  end

  def errors_on(violations, skill)
    violations.select { |v| v.skill == skill && v.severity == :error }
  end

  def test_clean_baseline_has_no_violations
    assert_empty guards
  end

  def test_unclassified_skill_errors
    refute_empty errors_on(guards(present: %w[a b c]), 'c')
  end

  def test_skill_in_both_lists_errors
    refute_empty errors_on(guards(exempt: { 'a' => 'no-model', 'b' => 'no-model' }, no_llm: %w[a b]), 'a')
  end

  def test_classified_but_absent_errors
    refute_empty errors_on(guards(guarded: %w[a ghost]), 'ghost')
  end

  def test_missing_block_errors
    v = errors_on(guards(blocks: { 'a' => nil }), 'a')
    assert_match(/first element/, v.first&.message)
  end

  def test_drifted_block_errors
    v = errors_on(guards(blocks: { 'a' => 'G. changed' }), 'a')
    assert_match(/canonical/, v.first&.message)
  end

  def test_block_without_link_line_errors
    refute_empty errors_on(guards(blocks: { 'a' => 'G.' }), 'a')
  end

  def test_spine_drift_errors
    refute_empty errors_on(guards(spine_quote: 'other'), 'security-spine')
  end

  def test_spine_missing_errors
    refute_empty errors_on(guards(spine_quote: nil), 'security-spine')
  end

  def test_unknown_reason_token_errors
    refute_empty errors_on(guards(exempt: { 'b' => 'trust me' }), 'b')
  end

  def test_no_model_without_marker_errors
    refute_empty errors_on(guards(no_llm: []), 'b')
  end

  def test_no_model_wired_to_agent_job_errors
    refute_empty errors_on(guards(job_agents: { 'b' => [false, true] }), 'b')
  end

  def test_operator_input_wired_to_agent_job_errors
    over = { exempt: { 'b' => 'operator-input' }, no_llm: [], job_agents: { 'b' => [true] } }
    refute_empty errors_on(guards(**over), 'b')
  end

  def test_agent_job_on_a_guarded_skill_is_fine
    assert_empty errors_on(guards(job_agents: { 'a' => [true] }), 'a')
  end

  def test_empty_guarded_list_errors
    refute_empty errors_on(guards(present: %w[b], guarded: [], blocks: {}), '_data/skills.yml')
  end

  def test_blank_guard_text_errors
    refute_empty errors_on(guards(guard_text: '  '), '_data/skills.yml')
  end

  def test_normalize_guard_collapses_quote_markers_and_whitespace
    assert_equal 'a b c', SkillsContract.normalize_guard("> a\r\n>  b\n>\n> c")
  end
end

class GuardExtractTest < Minitest::Test
  FIX = File.join(ROOT, 'test', 'fixtures', 'skills')
  OK = '**Guard.** Line one wraps onto line two. Rules: link.'

  def block(name)
    SkillsContract::Extract.first_blockquote(File.join(FIX, "#{name}.txt"))
  end

  def test_first_blockquote_after_the_title_is_read_and_normalized
    assert_equal OK, block('guard-ok')
  end

  def test_a_block_that_is_not_first_is_nil
    assert_nil block('guard-second')
  end

  # A line without `>` continues the quote's paragraph when rendered, so it is
  # read as part of the block and shows up as drift.
  def test_lazy_continuation_inside_the_block_is_part_of_it
    assert_includes block('guard-lazy'), 'lazily'
  end

  def test_lazy_continuation_after_the_block_is_drift
    v = SkillsContract.check_guards(
      present: %w[a], guarded: %w[a], exempt: {}, guard_text: '**Guard.** Line one wraps onto line two.',
      blocks: { 'a' => block('guard-lazy-after') }, spine_quote: '**Guard.** Line one wraps onto line two.',
      no_llm: [], job_agents: {}
    )
    assert(v.any? { |x| x.skill == 'a' && x.message.include?('canonical') })
  end

  def test_crlf_reads_the_same_as_lf
    assert_equal OK, block('guard-crlf')
  end

  def test_hash_inside_front_matter_is_not_the_title
    assert_equal OK, block('guard-frontmatter-hash')
  end

  def test_spine_quote_comes_from_section_one_only
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'spine.md')
      File.write(path, "# Spine\n\n## 1. Guard\nIntro.\n\n> one\n> two\n\n## 2. Other\n\n> three\n")
      assert_equal 'one two', SkillsContract::Extract.spine_guard_quote(path)
    end
  end

  def test_spine_quote_in_a_later_section_is_not_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'spine.md')
      File.write(path, "# Spine\n\n## 1. Guard\nIntro.\n\n## 2. Other\n\n> three\n")
      assert_nil SkillsContract::Extract.spine_guard_quote(path)
    end
  end

  def test_no_llm_marker_is_found_case_insensitively
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'SKILL.md')
      File.write(path, "# x\n\nDeterministic, **No LLM**.\n")
      assert SkillsContract::Extract.says_no_llm?(path)
      File.write(path, "# x\n\nA model reads it.\n")
      refute SkillsContract::Extract.says_no_llm?(path)
    end
  end

  def test_job_agents_resolve_aliases_against_the_template
    agents = SkillsContract::Extract.job_agents(File.join(ROOT, 'setup', 'config.template.yaml'),
                                                 'announcements' => 'release-announce')
    assert_equal [true], agents['release-announce']
    assert_equal [false], agents['label-sync']
  end
end

class GuardRepoTest < Minitest::Test
  E = SkillsContract::Extract

  def policy
    YAML.safe_load(File.read(File.join(ROOT, '_data', 'skills.yml')))
  end

  def live(present: nil, blocks: {})
    pol = policy
    guarded = pol['reads_untrusted'] || []
    exempt = pol['guard_exempt'] || {}
    present ||= E.present_skills(File.join(ROOT, 'skills'))
    md = ->(s) { File.join(ROOT, 'skills', s, 'SKILL.md') }
    real = (guarded & present).to_h { |s| [s, File.exist?(md.(s)) ? E.first_blockquote(md.(s)) : nil] }
    SkillsContract.check_guards(
      present: present, guarded: guarded, exempt: exempt, guard_text: pol['injection_guard'],
      blocks: real.merge(blocks),
      spine_quote: E.spine_guard_quote(File.join(ROOT, 'docs', 'reference', 'security-spine.md')),
      no_llm: exempt.keys.select { |s| File.exist?(md.(s)) && E.says_no_llm?(md.(s)) },
      job_agents: E.job_agents(File.join(ROOT, 'setup', 'config.template.yaml'), pol['job_aliases'] || {})
    )
  end

  def test_live_repo_has_no_guard_violations
    refute_empty policy['reads_untrusted'].to_a
    assert_empty live.map(&:to_line)
  end

  def test_removing_a_block_is_caught
    Dir.mktmpdir do |dir|
      src = File.read(File.join(ROOT, 'skills', 'pr-triage', 'SKILL.md'))
      path = File.join(dir, 'SKILL.md')
      File.write(path, src.lines.reject { |l| l.start_with?('>') }.join)
      v = live(blocks: { 'pr-triage' => E.first_blockquote(path) })
      assert(v.any? { |x| x.skill == 'pr-triage' })
    end
  end

  def test_new_unclassified_skill_is_caught
    present = E.present_skills(File.join(ROOT, 'skills')) + ['brand-new']
    assert(live(present: present).any? { |x| x.skill == 'brand-new' })
  end
end
