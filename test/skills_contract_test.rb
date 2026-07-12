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
  def test_present_skills_finds_the_nine
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

    # the seven known-missing skills are accounted for as planned (info)
    infos = v.select { |x| x.severity == :info }.map(&:skill)
    assert_includes infos, 'label-sync'
    assert_includes infos, 'chat-monitor'
  end
end
