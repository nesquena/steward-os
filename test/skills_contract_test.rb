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
    policy = YAML.safe_load(File.read(File.join(ROOT, '_data', 'skills.yml'), encoding: 'UTF-8')) || {}
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
    template = YAML.safe_load(File.read(File.join(ROOT, 'setup', 'config.template.yaml'), encoding: 'UTF-8'))
    dogfood = YAML.safe_load(File.read(File.join(ROOT, 'setup', 'config.yaml'), encoding: 'UTF-8'))

    assert_equal template.keys.sort, dogfood.keys.sort
    assert_equal REQUIRED_CONFIG_KEYS.sort, template.fetch('issue_capture').keys.sort
    assert_equal template.fetch('issue_capture').keys.sort, dogfood.fetch('issue_capture').keys.sort
  end

  def test_issue_capture_is_runnable_wired_and_not_still_planned
    template = YAML.safe_load(File.read(File.join(ROOT, 'setup', 'config.template.yaml'), encoding: 'UTF-8'))
    jobs = template.fetch('scheduled_jobs').fetch('jobs').to_h { |job| [job.fetch('name'), job] }
    policy = YAML.safe_load(File.read(File.join(ROOT, '_data', 'skills.yml'), encoding: 'UTF-8'))
    capture = File.read(File.join(ROOT, 'skills', 'issue-capture', 'SKILL.md'), encoding: 'UTF-8')

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
    capture = File.read(File.join(ROOT, 'skills', 'issue-capture', 'SKILL.md'), encoding: 'UTF-8')
    watchdog = File.read(File.join(ROOT, 'skills', 'action-watchdog', 'SKILL.md'), encoding: 'UTF-8')
    triage = File.read(File.join(ROOT, 'skills', 'issue-triage', 'SKILL.md'), encoding: 'UTF-8')
    community = File.read(File.join(ROOT, 'docs', 'lifecycle', 'community.md'), encoding: 'UTF-8')

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
    assert_includes watchdog, '**Host closes**'
    refute_includes watchdog, '**Autonomous issue files**', 'filing a capture is Band C: nothing files autonomously'
    assert_includes community, 'reconcile it against the live tracker'
    assert_includes community, 'surface it to a human, who files it (Band C)'
    assert_includes community, '`chat-monitor` only reads'
    assert_includes community, '`issue-capture` owns the untrusted-data guard'
    assert_includes community, 'Chat monitoring stays off until the shared capture core'
    refute_includes triage, '**Capture-dedupe.**', 'pre-tracker capture has one procedural owner'
  end
end

# --- Each repository's host_closes_on_merge is honoured wherever it decides something ---
class HostClosingContractTest < Minitest::Test
  # Each repository's host_closes_on_merge decides what three skills and the setup interview do. Read
  # with whitespace folded, so a re-wrap doesn't break the pin.
  def test_host_closing_is_honoured_wherever_it_decides_something
    read = ->(*path) { File.read(File.join(ROOT, *path), encoding: 'UTF-8').gsub(/\s+/, ' ') }
    autoclose = read.call('skills', 'issue-autoclose', 'SKILL.md')
    release = read.call('skills', 'release-pipeline', 'SKILL.md')
    watchdog = read.call('skills', 'action-watchdog', 'SKILL.md')
    setup = read.call('setup', 'setup-interview.md')
    issue_lifecycle = read.call('docs', 'lifecycle', 'issue-lifecycle.md')
    pr_lifecycle = read.call('docs', 'lifecycle', 'pr-lifecycle.md')

    assert_includes autoclose, 'Skip a repository whose `host_closes_on_merge` is `true`'
    assert_includes autoclose, "That's a wait, not a hold: leave the issue open and unrouted"
    assert_includes autoclose, 'however long ago the PR merged'
    assert_includes autoclose, "Under `style: continuous` no release tag is coming, so there's nothing to " \
                               'wait for: route the candidate to a human'
    assert_includes autoclose, "Skip a repository whose host isn't github.com, too"
    assert_includes autoclose, 'Only closes on github.com repositories.'
    assert_includes autoclose, "Read `style` as the config lint's `normalize_job_name` does: drop invisible " \
                               'format characters, trim surrounding whitespace, and ignore case'
    assert_includes issue_lifecycle, 'stays unrouted until a release contains the merge'
    assert_includes pr_lifecycle, "comment on them, and don't reopen them"
    assert_includes release, 'On a repository whose `host_closes_on_merge` is `true`, the host closed ' \
                             'those issues at merge: comment on them, close any it left open'
    assert_includes watchdog, 'for each repository whose `host_closes_on_merge` is `false`'
    assert_includes watchdog, 'On any other host (Gitea, Forgejo, or a self-managed instance), this ' \
                              "check can't tell from the name which API the host speaks"
    assert_includes watchdog, "While a repository is declared `true`, drop its start"
    assert_includes setup, 'untick **Auto-close issues with merged linked pull requests**'
    assert_includes setup, 'untick **Auto-close referenced issues on default branch**'
    who = 'closed at release (by `release-pipeline` step 6 for the PRs it ships, by hand otherwise)'
    assert_includes autoclose, "on any other host the issue is #{who}"
    assert_includes autoclose, "On any other host it closes nothing, and the issue is #{who}"
    assert_includes issue_lifecycle, "On other hosts the issue is #{who}"
    assert_includes setup, "an issue the host left open is #{who}"
    assert_includes autoclose, "drop a row this job wrote whose issue isn't among this run's candidates " \
                               '(it closed, lost its merged closing link, or sits in a repository this step skips)'
    assert_includes autoclose, 'a listing that fails drops nothing and alarms (step 7)'
    assert_includes autoclose, 'Its index row names this job and keeps the step that routed it (2, 3, 4 or 5) ' \
                               "and the time of the reporter's latest comment or reaction"
    # Host scope: only github.com closes autonomously; the who-closes string above doesn't carry that.
    assert_includes issue_lifecycle, 'The safe autonomous gate (Band A *with watchdog*, github.com repositories only)'
    assert_includes setup, '`issue-autoclose` closes only on github.com; on any other host, an issue the host left ' \
                          'open is closed at release'
    # The reconcile runs after selection, and only on a complete listing.
    assert_includes autoclose, '1. **Read `config.yaml`, select candidates and reconcile.** Load `repositories:`'
    assert_includes autoclose, 'Then reconcile the index: drop a row this job wrote'
    assert_operator autoclose.index('consider every **open** issue'), :<,
                    autoclose.index('Then reconcile the index: drop a row this job wrote'),
                    'reconcile after selection, so "not among this run\'s candidates" is decidable'
    assert_includes autoclose, 'Reconcile only after every repository was listed in full: a listing that fails ' \
                               'drops nothing and alarms (step 7)'
    assert_includes autoclose, 'part of the "shipped" notion'
  end
end

class ProjectShapeContractTest < Minitest::Test
  # Section 0 of the setup interview, the setup skill and the template header. Read with whitespace
  # folded, so a re-wrap doesn't break the pin.
  def read(*path)
    File.read(File.join(ROOT, *path), encoding: 'UTF-8').gsub(/\s+/, ' ')
  end

  def section0
    setup = read('setup', 'setup-interview.md')
    from = setup.index('## Section 0 ')
    upto = setup.index('## Section 1 ')
    assert from && upto && from < upto, 'Section 0 must come before Section 1'
    setup[from...upto]
  end

  def setup_step(num)
    skill = read('skills', 'project-system-setup', 'SKILL.md')
    skill[/ #{num}\. \*\*.*?(?= #{num + 1}\. \*\*|\z)/m] or flunk("step #{num} missing")
  end

  def test_interview_asks_shape_first
    s = section0
    ['**A. Public or private?**', '**B. Who files issues?**', '**C. Do you tag releases?**',
     '**D. Do issues live on the code host or in a separate tracker?**'].each { |q| assert_includes s, q }
    assert_includes s, "lettered A-D so the numbered questions keep their numbers"
    full = read('setup', 'setup-interview.md')
    (1..22).each { |n| assert_match(/ #{n}\. \*\*/, full, "question #{n} lost its number") }
    # Section 0 cites question 20 as the security contact and question 22 as the alarms route.
    assert_includes full[/ 20\. \*\*.*?(?= 21\. \*\*)/m].to_s, '`security.security_contact`'
    assert_includes full[/ 22\. \*\*.*?(?=---| 23\. \*\*|\z)/m].to_s, 'where should watchdog alarms go?'
  end

  def test_a_human_confirms_each_marked_block
    assert_includes section0, 'A human confirms each block. The agent never marks a block on its own.'
  end

  def test_a_marked_block_is_deleted_or_empty
    assert_includes section0, "Marking a block means deleting it or leaving it `{}`, because the config can't both " \
                              "say a block doesn't apply and configure it."
  end

  def test_shape_never_skips_the_divert_questions
    assert_includes section0, 'Shape answers never skip question 20 (the security contact) or question 22 ' \
                              '(the alarms route).'
  end

  def test_a_block_with_history_stays_disabled
    assert_includes section0, "A block with history isn't marked: deleting it would lose its paths and state, and " \
                              'capture state is the audit trail for diverted vulnerabilities. Turn it off instead'
    assert_includes section0, 'Turn it off instead, with whatever depends on it, so the config still lints. For ' \
                              '`issue_capture`: `issue_capture.enabled: false`, the `issue-capture` job ' \
                              '`enabled: false`, and `chat.monitor: false`, since chat monitoring needs capture.'
    assert_includes section0, '`labels` has no flag of its own: disable the `label-sync` job and keep the taxonomy'
    assert_includes section0, '`trust` turns off only by blanking `ledger_path`, which drops the path but not the ' \
                              'ledger file: keep the path in a TODO.'
  end

  def test_a_marked_block_skips_only_the_part_that_needs_it
    assert_includes section0, 'A skill reads nothing from a marked block and infers no default for it. Only the part ' \
                              'of a step that needs the block is skipped; the rest of that step still runs.'
  end

  def test_shape_answers_are_re_asked
    assert_includes section0, 'The shape answers are not stored. A re-run asks them again. The marker keeps the outcome.'
  end

  def test_separate_tracker_warning_is_expected
    assert_includes section0, 'With a separate tracker (question D), question 2 says when its host-closing change applies.'
    q2 = read('setup', 'setup-interview.md')[/ 2\. \*\*.*?(?= 3\. \*\*)/m]
    assert_includes q2, "If it doesn't (issues are turned off on the repository), the settings change doesn't " \
                        'apply: record `host_closes_on_merge: false` and skip it. The `host_closing_unwatched` ' \
                        'warning then stands, and that is expected'
    assert_includes q2, 'If it still takes issues, ask this question as written.'
    assert_includes q2, 'Either way, unless every merge is the release, ask whether the tracker\'s own integration ' \
                        'closes or moves an issue when a linked PR merges'
    assert_includes q2, "Where it can't, the release names the version on those issues as `release-pipeline` step 6 says."
    assert_includes q2, '`host_closes_on_merge` describes only the code host.'
  end

  def test_board_location_has_a_fallback
    assert_includes section0, 'set `scoreboard-refresh` to `enabled: false` and leave a TODO naming the location'
    assert_includes read('setup', 'setup-interview.md'),
                    'or that question was skipped (Section 0), set `scoreboard-refresh` to `enabled: false`.'
    assert_includes setup_step(5), 'If Section 0 left `scoreboard-refresh` disabled for want of a location, keep it ' \
                                   'disabled and carry the TODO.'
  end

  def test_lint_warns_the_divert_destinations_are_unverified
    assert_includes section0, "The lint then warns about each of the two it can't verify as private (a blank " \
                              'value, or the `github-advisory` contact, gets no warning): confirm each destination ' \
                              'with the human.'
  end

  def test_board_goes_only_where_the_issues_are_as_private
    assert_includes section0, 'The board, its machine-readable artifact and any digest of its rows go only where ' \
                              'they are no more visible than the issues they list; history counts, so re-check ' \
                              'before any visibility change.'
  end

  def test_setup_verification_checks_the_marker
    verification = read('skills', 'project-system-setup', 'SKILL.md').split('## Verification').last
    assert_includes verification, 'Every block the human confirmed as not applicable is listed under ' \
                                  '`not_applicable` and is deleted or `{}`.'
    assert_includes verification, 'or its failure to run is a TODO'
  end

  def test_fallback_index_limit_is_stated
    assert_includes section0, "When `issue_capture` is off or marked and no announcements or autoclose job is " \
                              "enabled, the lint doesn't check that the pull index (the divert's last fallback) " \
                              'is private: tell the human.'
  end

  def test_template_header_separates_blank_from_marked
    tpl = File.read(File.join(ROOT, 'setup', 'config.template.yaml'), encoding: 'UTF-8').gsub(/\s*\n#\s*/, ' ')
    assert_includes tpl, 'A blank or "skip" optional section is unanswered: it stays disabled and becomes a TODO. ' \
                         "A block that doesn't apply is a decision: list it under `not_applicable`."
  end

  def test_setup_skill_runs_the_lint
    step = setup_step(4)
    assert_includes step, 'run `bin/config-lint` on it from the steward-os checkout'
    assert_includes step, "A lint that can't run becomes a TODO, never a pass."
    assert_includes read('skills', 'project-system-setup', 'SKILL.md'), 'project shape (Section 0)'
  end

  # The numbered step `num` of a skill, whitespace-folded, up to the next numbered step.
  def skill_step(skill, num)
    text = read('skills', skill, 'SKILL.md')
    text[/ #{num}\. \*\*.*?(?= #{num + 1}\. \*\*|\z)/m] or flunk("#{skill} step #{num} missing")
  end

  def test_judgment_only_run_keeps_the_divert
    t = read('skills', 'issue-triage', 'SKILL.md')
    t = t[t.index('## Steps')...t.index(' 1. **')]
    assert_includes t, 'A judgment-only run is a person\'s supervised run: it records judgments and skips steps 3, 5 ' \
                       'and 6 (the reply, the labels and milestone, the sprint-candidate mark).'
    assert_includes t, 'Step 2, the vulnerability check, always runs: skipping the public steps never skips step 2, ' \
                       'and a suspected vulnerability still gets no judgment.'
    assert_includes t, '"New" keeps its meaning in a judgment-only run: it adds no backfill.'
    assert_includes t, 'A judgment-only run marks an issue handled like any other run; the mark gates only step ' \
                       '4\'s "new", so a later full run still runs steps 3, 5 and 6 on it.'
  end

  def test_marked_labels_mean_no_labels
    assert_includes skill_step('issue-triage', 5),
                    'If `labels` is listed under `not_applicable`, apply no taxonomy label.'
  end

  # Like skill_step, but stops at the next `## ` heading so a sentence moved out of the step fails the pin.
  def skill_step_only(skill, num)
    skill_step(skill, num).split(/ ## /).first
  end

  def test_marked_trust_means_no_ledger_update
    marked = 'If `trust` is listed under `not_applicable`, or `trust.ledger_path` is blank, skip the ledger update ' \
             'and record no trust event.'
    assert_includes skill_step_only('release-pipeline', 6), marked
    assert_includes skill_step_only('release-pipeline', 6),
                    "Treat an issue a separate tracker's own integration closed or moved at merge the same way."
    verification = read('skills', 'release-pipeline', 'SKILL.md').split('## Verification').last
    assert_includes verification, 'With `trust` listed under `not_applicable`, or a blank `trust.ledger_path`, no ' \
                                  'ledger event was written.'
  end

  def test_marked_community_means_no_chat_source
    assert_includes skill_step('issue-capture', 1),
                    'If `community` is listed under `not_applicable`, there is no chat source: skip chat reads and ' \
                    'infer no chat default.'
  end

  def test_default_weights_are_for_issues
    step = skill_step('triage-scoreboard', 4)
    assert_includes step, 'With no weights set by the project, weight an issue\'s judgment dimensions equally (the ' \
                          'default rubric\'s `scope_fit`, `criticality` and `risk`, or a replacement\'s own) and use ' \
                          'the mechanical dimensions only to break ties. ' \
                          'Weights the project sets replace the equal weights. The default covers issues only.'
    assert_includes step, 'Rank PRs and issues separately; sort issues on the judgment dimensions\' weighted sum first'
    playbook = read('docs', 'playbooks', 'triage-scoreboard.md')
    assert_includes playbook, 'With no weights set by the project, an issue\'s judgment dimensions weigh equally and ' \
                              'the mechanical dimensions only break ties. Weights the project sets replace the equal ' \
                              'weights. The default covers issues only.'
    assert_includes playbook, 'Judgment dimensions should outweigh mechanical ones'
  end

  def test_board_rule_covers_every_output
    sentence = 'The board, its machine-readable artifact and any digest of its rows go only where they are no more ' \
               'visible than the issues they list; history counts, so re-check before any visibility change. ' \
               'Nothing mechanical enforces this rule.'
    assert_includes skill_step_only('triage-scoreboard', 7), sentence
    assert_includes read('docs', 'playbooks', 'triage-scoreboard.md'), sentence
  end

  def test_a_fact_missing_on_some_items_is_no_zero
    pitfalls = read('skills', 'triage-scoreboard', 'SKILL.md').split('## Pitfalls').last.split('## Verification').first
    assert_includes pitfalls, '**A missing fact is not a zero.** A fact missing on some items, not all, is reported ' \
                              'and never treated as zero. ' \
                              'The inert-dimension rule covers a fact missing on every item.'
  end

  def test_quickstart_does_not_require_github
    q = read('quickstart.md')
    refute_includes q, 'A **GitHub repository**'
    assert_includes q, 'The examples use a GitHub repository and the `gh` CLI. Your tracker and host can differ.'
  end

  def test_quickstart_names_ruby_for_the_lint
    assert_includes read('quickstart.md'), 'Ruby, to run `bin/config-lint` from the steward-os checkout.'
  end

  def tracker_section
    q = read('quickstart.md')
    from = q.index('## Your tracker is your wiring') or flunk('tracker section missing')
    q[from..].split(/ ## \d\. /).first
  end

  def test_tracker_section_keeps_the_bands
    s = tracker_section
    assert_includes s, 'Every write keeps its band, from `autonomy:` or from the skill that makes it, whatever the tool. ' \
                       "A private tracker doesn't lower a band."
    assert_includes s, 'steward-os ships no adapter and names no tracker.'
  end

  def test_missing_fact_is_never_zero
    assert_includes tracker_section, 'If your tracker cannot supply a fact, the skill reports it as missing ' \
                                     'and never treats it as zero.'
  end

  def test_skills_already_say_what_they_need
    assert_includes tracker_section, 'Each `SKILL.md` names the facts it reads.'
  end

  def shape_rows
    t = File.read(File.join(ROOT, 'docs', 'reference', 'adoption-levels.md'), encoding: 'UTF-8')
    lines = t.lines.map(&:strip)
    head = lines.index { |l| l.start_with?('| Shape ') } or flunk('shape table missing')
    cols = lines[head].split('|').map(&:strip)[1..]
    skills_at = cols.index('Skills') or flunk('Skills column missing')
    assert_includes cols, 'Blocks usually marked'
    lines[(head + 1)..].reject { |l| l =~ /\A\|\s*-/ }.take_while { |l| l.start_with?('|') }.map { |l| l.split('|').map(&:strip)[1..] }
                       .each { |r| r.define_singleton_method(:skills) { self[skills_at] } }
  end

  def test_shape_table_has_three_shapes
    t = read('docs', 'reference', 'adoption-levels.md')
    labels = shape_rows.map(&:first)
    ['public with outside reporters and tags', 'private team with a separate tracker', 'private solo'].each do |s|
      assert_includes labels, s
    end
    assert_operator shape_rows.size, :>=, 3
    assert_operator t.index('| Shape '), :<, t.index('_Related:')
    assert_operator t.index('| Level | What'), :<, t.index('| Shape ')
  end

  def test_every_skill_in_the_table_exists
    shape_rows.each do |r|
      names = r.skills.scan(/`([^`]+)`/).flatten
      assert_equal r.skills.gsub(/`[^`]+`|[ ,]/, ''), '', "Skills cell holds more than skill names: #{r.skills}"
      refute_empty names, "row has no skills: #{r.first}"
      names.each { |n| assert File.directory?(File.join(ROOT, 'skills', n)), "no skills/#{n}/" }
    end
  end

  def test_private_team_row_names_the_first_job
    row = shape_rows.find { |r| r.first.include?('private team') }
    assert_includes row.skills, '`triage-scoreboard`'
    assert_includes row.skills, '`issue-triage`'
    %w[community issue_capture labels trust].each { |b| assert_includes row.join(' '), "`#{b}`" }
    levels = read('docs', 'reference', 'adoption-levels.md')
    assert_includes levels, 'That run writes judgments and skips replies, labels and sprint-candidate marks.'
    assert_includes levels, 'The vulnerability divert still runs.'
    assert_includes levels, '`issue-triage` does no backfill, so that run reaches the existing backlog only for the ' \
                            'issues a person names.'
    solo = shape_rows.find { |r| r.first == 'private solo' }
    assert_includes solo.skills, '`release-pipeline`' # pr-deep-review hands off to it
    assert_includes levels, 'A team with pull requests adds `coding-principles`, `pr-triage`, `pr-deep-review` and ' \
                            '`release-pipeline` once Level 2 is steady.'
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

  # Nothing may come before the title: prose there would read ahead of the guard,
  # and a title plus guard inside an HTML comment or a fence renders as no
  # blockquote at all while the real title below it carries none.
  def test_prose_before_the_title_is_nil
    assert_nil block('guard-prose-before-title')
  end

  def test_a_title_and_guard_inside_an_html_comment_is_nil
    assert_nil block('guard-title-in-comment')
  end

  def test_a_title_and_guard_inside_a_fence_is_nil
    assert_nil block('guard-title-in-fence')
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
    assert_equal [false], agents['release-announce']
    assert_equal [false], agents['label-sync']
  end
end

class GuardRepoTest < Minitest::Test
  E = SkillsContract::Extract

  def policy
    YAML.safe_load(File.read(File.join(ROOT, '_data', 'skills.yml'), encoding: 'UTF-8'))
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
      src = File.read(File.join(ROOT, 'skills', 'pr-triage', 'SKILL.md'), encoding: 'UTF-8')
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
