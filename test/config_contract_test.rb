# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'English'
require_relative '../lib/config_contract'

FIXTURE_ROOT = File.expand_path('fixtures/config', __dir__)

class ExtractKeyPathsTest < Minitest::Test
  def paths(node)
    ConfigContract::Extract.key_paths(node)
  end

  def test_nested_hash_becomes_dotted_paths
    assert_equal %w[a.b.c], paths({ 'a' => { 'b' => { 'c' => 1 } } })
  end

  def test_list_elements_normalize_to_brackets
    node = { 'repos' => [{ 'name' => 'x' }, { 'name' => 'y' }] }
    assert_equal %w[repos[].name], paths(node).uniq
  end

  def test_empty_collection_is_itself_a_leaf
    assert_equal %w[a], paths({ 'a' => [] })
    assert_equal %w[b], paths({ 'b' => {} })
  end

  def test_walk_stops_at_opaque_subtrees
    node = { 'labels' => { 'area' => { 'map' => { 'skills/**' => 'area:skills' } } } }
    assert_equal %w[labels.area.map], paths(node)
  end

  def test_opaque_list_stays_shallow_for_size_buckets
    node = { 'labels' => { 'size' => { 'buckets' => { 'S' => 50, 'XL' => nil } } } }
    assert_equal %w[labels.size.buckets], paths(node)
  end
end

class ExtractEmptyCollectionPathsTest < Minitest::Test
  def empties(node)
    ConfigContract::Extract.empty_collection_paths(node)
  end

  def test_finds_empty_hash_and_empty_array_leaves_only
    node = { 'a' => [], 'b' => {}, 'c' => 1, 'd' => { 'e' => [] } }
    assert_equal %w[a b d.e].sort, empties(node).sort
  end
end

class ExtractLoadTest < Minitest::Test
  def test_load_returns_parsed_hash
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'c.yaml')
      File.write(path, "a:\n  b: 1\n")
      assert_equal({ 'a' => { 'b' => 1 } }, ConfigContract::Extract.load(path))
    end
  end

  def test_load_raises_a_clear_message_on_malformed_yaml
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'bad.yaml')
      File.write(path, "a:\n  - [unclosed\n")
      err = assert_raises(RuntimeError) { ConfigContract::Extract.load(path) }
      assert_match(/could not parse/, err.message)
      assert_match(/bad\.yaml/, err.message)
    end
  end

  def test_load_of_empty_file_returns_empty_hash
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'empty.yaml')
      File.write(path, '')
      assert_equal({}, ConfigContract::Extract.load(path))
    end
  end

  # Pins that conversion stays YAML.safe_load. An alias carries no tag, so it
  # reaches conversion; safe_load refuses it, node.to_ruby would accept it.
  def test_read_converts_with_the_safe_loader
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'c.yaml')
      File.write(path, "a: &x 1\nb: *x\n")
      err = assert_raises(RuntimeError) { ConfigContract::Extract.read(path) }
      assert_match(/could not parse/, err.message)
    end
  end

  def test_read_of_an_empty_file_is_an_empty_hash
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'c.yaml')
      File.write(path, '')
      assert_equal [{}, []], ConfigContract::Extract.read(path)
    end
  end

  def test_read_returns_parse_violations_instead_of_a_hash
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'c.yaml')
      File.write(path, "a: 1\na: 2\n")
      config, violations = ConfigContract::Extract.read(path)
      assert_nil config
      assert_equal %i[duplicate_key], violations.map(&:rule)
    end
  end
end

# --- repo_relative? / escapes_repo_root?: the privacy-classification primitive ---
class ParseRulesTest < Minitest::Test
  def rules(text) = ConfigContract::ParseRules.violations(text).map(&:rule)
  def keys(text)  = ConfigContract::ParseRules.violations(text).map(&:key)

  def test_a_plain_single_document_is_clean
    assert_empty rules("a: 1\nb:\n  c: 2\n")
  end

  def test_a_leading_marker_or_an_end_marker_is_still_one_document
    assert_empty rules("---\na: 1\n")
    assert_empty rules("a: 1\n...\n")
  end

  def test_an_empty_or_comment_only_file_has_no_parse_violations
    assert_empty rules('')
    assert_empty rules("# only a comment\n")
  end

  def test_a_second_document_is_refused_even_when_empty
    assert_equal %i[multiple_documents], rules("a: 1\n---\nb: 2\n")
    assert_equal %i[multiple_documents], rules("a: 1\n---\n")
    assert_equal ['(document)'], keys("a: 1\n---\nb: 2\n")
  end

  def test_a_repeated_top_level_key_is_refused_with_both_lines
    v = ConfigContract::ParseRules.violations("a: 1\nb: 2\na: 3\n")
    assert_equal %i[duplicate_key], v.map(&:rule)
    assert_equal 'a', v.first.key
    assert_match(/\b1\b/, v.first.message)
    assert_match(/\b3\b/, v.first.message)
  end

  def test_a_repeated_key_is_found_at_depth_and_in_lists
    assert_equal ['x.y'], keys("x:\n  y: 1\n  y: 2\n")
    assert_equal ['scheduled_jobs.jobs[0].name'],
                 keys("scheduled_jobs:\n  jobs:\n    - { name: a, name: b }\n")
  end

  def test_keys_that_resolve_to_the_same_ruby_key_are_duplicates
    assert_includes rules("m:\n  yes: 1\n  true: 2\n"), :duplicate_key
    assert_includes rules("m:\n  ~: 1\n  null: 2\n"), :duplicate_key
    assert_includes rules("m:\n  16: 1\n  0x10: 2\n"), :duplicate_key
  end

  def test_opaque_subtrees_are_checked_too
    assert_equal ['labels.area.map.a/**'],
                 keys("labels:\n  area:\n    map:\n      \"a/**\": x\n      \"a/**\": y\n")
  end

  def test_a_merge_key_is_refused_plain_or_quoted
    assert_equal %i[merge_key], rules("a: 1\n<<: {a: 2}\n")
    assert_equal %i[merge_key], rules("a: 1\n\"<<\": {a: 2}\n")
  end

  def test_any_explicit_tag_is_refused
    assert_includes rules("!!binary aXNzdWVfY2FwdHVyZQ==: 1\n"), :explicit_tag
    assert_includes rules("a: !foo 1\n"), :explicit_tag
    assert_includes rules("a: !ruby/object:Gem::Version {version: '1'}\n"), :explicit_tag
    assert_includes rules("a: !!str 1\n"), :explicit_tag
  end

  def test_inspection_never_instantiates_a_tagged_object
    ObjectSpace.garbage_collect
    before = ObjectSpace.each_object(Gem::Version).count
    ConfigContract::ParseRules.violations("a: !ruby/object:Gem::Version {version: '99.9'}\n")
    assert_operator ObjectSpace.each_object(Gem::Version).count, :<=, before
  end

  def test_unparseable_text_raises
    assert_raises(Psych::SyntaxError) { ConfigContract::ParseRules.violations("a: [unclosed\n") }
  end
end

class RepoRelativeTest < Minitest::Test
  def rel(path)
    ConfigContract.repo_relative?(path)
  end

  def test_plain_relative_paths_are_repo_relative
    assert rel('state/index.md')
    assert rel('./index.md')
    assert rel('a/b/../c.md') # normalizes to a/c.md, still inside
    assert rel('index.md')
  end

  def test_absolute_and_home_and_uri_are_not_repo_relative
    refute rel('/srv/steward/index.md')
    refute rel('~/index.md')
    refute rel('https://example.com/x')
    refute rel('file:///etc/passwd')
  end

  def test_dotdot_escape_is_not_repo_relative
    refute rel('../public-site/vulns.md')
    refute rel('state/../../outside.md')
  end

  def test_resolving_back_to_the_repo_root_is_not_strictly_inside
    refute rel('state/../') # depth 0 — the root itself, not a file inside
  end

  # Regression: a backslash-rooted or UNC path must be classified outside the
  # repo, the same as its forward-slash form. Before separator normalization ran
  # first, these slipped through as repo-relative and were omitted from the
  # unverifiable warning — the double-suppression the traversal fix closed.
  def test_backslash_rooted_and_unc_paths_are_not_repo_relative
    refute rel('\\srv\\steward\\index.md'), 'backslash-rooted path escapes'
    refute rel('\\\\host\\share\\index.md'), 'UNC path is outside the repo'
    refute rel('..\\public\\x.md'), 'backslash traversal escapes'
    refute rel('state\\..\\..\\x'), 'mixed-separator traversal escapes'
  end

  def test_drive_qualified_paths_are_not_repo_relative
    refute rel('C:\\steward\\index.md')
    refute rel('C:/steward/index.md')
    refute rel('C:outside\\index.md'), 'drive-relative path is outside too'
  end
end


class ShapeTest < Minitest::Test
  TEMPLATE = {
    'project' => { 'name' => '', 'repo' => '' },
    'issue_capture' => { 'enabled' => false, 'sources' => [] },
    'scheduled_jobs' => {
      'jobs' => [
        { 'name' => 'a', 'every' => '1h', 'enabled' => false },
        { 'name' => 'b', 'cron' => '30 8 * * *', 'enabled' => false }
      ]
    }
  }.freeze

  def rules(violations)
    violations.map(&:rule)
  end

  def check(config)
    ConfigContract.check(config: config, template: TEMPLATE)
  end

  def test_matching_shape_reports_no_shape_violations
    refute_includes rules(check(TEMPLATE)), :unknown_key
    refute_includes rules(check(TEMPLATE)), :missing_key
  end

  def test_unknown_key_is_an_error
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['issue_captures'] = { 'enabled' => true }
    v = check(cfg).find { |x| x.rule == :unknown_key }
    assert_equal :error, v.severity
    assert_equal 'issue_captures.enabled', v.key
  end

  def test_missing_key_is_an_error
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['project'].delete('name')
    v = check(cfg).find { |x| x.rule == :missing_key }
    assert_equal :error, v.severity
    assert_equal 'project.name', v.key
  end

  def test_unknown_key_where_the_template_nests_a_mapping_says_so
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['issue_capture'] = 'skip'
    v = check(cfg).find { |x| x.rule == :unknown_key }
    assert_equal :error, v.severity
    assert_equal 'issue_capture', v.key
    assert_match(/nests keys under this one — expected a mapping, not a scalar/, v.message)
  end

  def test_populated_list_satisfies_an_empty_template_list
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['issue_capture']['sources'] = %w[email webform]
    assert_empty check(cfg).select { |x| %i[unknown_key missing_key].include?(x.rule) }
  end

  def test_job_with_neither_every_nor_cron_is_an_error
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'][0].delete('every')
    v = check(cfg).find { |x| x.rule == :job_schedule_alternation }
    assert_equal :error, v.severity
    assert_match(/exactly one/, v.message)
  end

  def test_job_with_both_every_and_cron_is_an_error
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'][0]['cron'] = '0 * * * *'
    assert_includes rules(check(cfg)), :job_schedule_alternation
  end

  def test_job_with_a_blank_schedule_value_is_an_error
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'][0]['every'] = ''
    v = check(cfg).find { |x| x.rule == :job_schedule_blank }
    assert_equal :error, v.severity
    assert_match(/not a schedule/, v.message)
  end

  def test_job_with_a_null_cron_is_an_error
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'][1].delete('cron')
    cfg['scheduled_jobs']['jobs'][1]['cron'] = nil
    assert_includes rules(check(cfg)), :job_schedule_blank
  end

  def test_job_with_an_nbsp_only_schedule_is_an_error
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'][0]['every'] = "\u00A0"
    assert_includes rules(check(cfg)), :job_schedule_blank
  end

  def test_job_with_a_non_string_schedule_is_an_error_and_reports_the_value
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'][0]['every'] = 3600
    v = check(cfg).find { |x| x.rule == :job_schedule_blank }
    assert_equal :error, v.severity
    assert_match(/non-blank string/, v.message)
    assert_match(/3600/, v.message)
  end

  def test_missing_cron_on_a_job_is_not_a_missing_key
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'] = [{ 'name' => 'a', 'every' => '1h', 'enabled' => false }]
    assert_empty check(cfg).select { |x| x.rule == :missing_key }
  end

  def test_empty_config_list_satisfies_a_populated_template_list
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs']['jobs'] = []
    assert_empty check(cfg).select { |x| %i[unknown_key missing_key].include?(x.rule) }
  end

  def test_empty_config_hash_satisfies_a_populated_template_subtree
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs'] = {}
    assert_empty check(cfg).select { |x| %i[unknown_key missing_key].include?(x.rule) }
  end

  def test_nil_ancestor_does_not_suppress_missing_keys
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs'] = nil
    assert_includes rules(check(cfg)), :missing_key,
                    'a nil ancestor is not an empty collection — suppressing here would be fail-open'
  end

  def test_scalar_ancestor_does_not_suppress_missing_keys
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['scheduled_jobs'] = 'yes'
    assert_includes rules(check(cfg)), :missing_key
  end

  def test_non_mapping_document_is_an_error
    v = ConfigContract.check(config: [], template: TEMPLATE)
    assert_equal :error, v.find { |x| x.rule == :not_a_mapping }.severity
    assert_includes v.map(&:rule), :phases_skipped,
                    'a suppressing error must always announce the suppression'
  end

  def test_shape_error_suppresses_later_phases
    cfg = Marshal.load(Marshal.dump(TEMPLATE))
    cfg['bogus'] = 1
    v = check(cfg)
    assert_includes rules(v), :unknown_key
    assert_includes rules(v), :phases_skipped
  end
end

# --- Phase 2: types ---
class TypeTest < Minitest::Test
  def base
    {
      'repositories' => [{ 'visibility' => 'public' }],
      'community' => { 'chat' => { 'monitor' => false, 'platform' => '', 'capture_reaction' => '' } },
      'issue_capture' => {
        'enabled' => false, 'capture_marker' => '', 'queue_path' => '',
        'ledger_path' => '', 'checkpoint_path' => '',
        'max_per_run' => 10, 'max_public_files_per_run' => 0
      },
      'security' => { 'security_contact' => '', 'security_sensitive_surfaces' => [] },
      'secrets' => { 'execute_contributor_code' => false, 'sandbox_available' => false },
      'scheduled_jobs' => {
        'jobs' => [{ 'name' => 'action-watchdog', 'every' => '6h', 'enabled' => false }],
        'outputs' => { 'index_path' => '', 'digest_to' => '', 'alarms_to' => '' }
      }
    }
  end

  def check(config)
    ConfigContract.check(config: config, template: base)
  end

  def find(config, rule)
    check(config).find { |x| x.rule == rule }
  end

  def test_string_false_is_not_a_boolean
    cfg = base
    cfg['issue_capture']['enabled'] = 'false'
    v = find(cfg, :type_boolean)
    assert_equal :error, v.severity
    assert_equal 'issue_capture.enabled', v.key
    assert_match(/String/, v.message)
  end

  def test_real_boolean_passes
    assert_nil find(base, :type_boolean)
  end

  def test_integer_where_a_string_belongs_is_an_error
    cfg = base
    cfg['scheduled_jobs']['outputs']['alarms_to'] = 42
    assert_equal 'scheduled_jobs.outputs.alarms_to', find(cfg, :type_string).key
  end

  def test_blank_string_is_a_valid_string
    assert_nil find(base, :type_string)
  end

  def test_negative_bound_is_an_error
    cfg = base
    cfg['issue_capture']['max_per_run'] = -1
    assert_equal 'issue_capture.max_per_run', find(cfg, :type_non_negative_integer).key
  end

  def test_misspelled_visibility_is_an_error
    cfg = base
    cfg['repositories'][0]['visibility'] = 'publik'
    v = find(cfg, :type_enum)
    assert_equal 'repositories[0].visibility', v.key
    assert_match(/public/, v.message)
  end

  def test_non_boolean_job_enabled_is_an_error
    cfg = base
    cfg['scheduled_jobs']['jobs'][0]['enabled'] = 'yes'
    assert_equal 'scheduled_jobs.jobs[0].enabled', find(cfg, :type_boolean).key
  end

  def test_security_sensitive_surfaces_must_be_an_array_of_strings
    cfg = base
    cfg['security'] = { 'security_contact' => '', 'security_sensitive_surfaces' => { 'auth' => true } }
    v = find(cfg, :type_string_array)
    assert_equal :error, v.severity
    assert_equal 'security.security_sensitive_surfaces', v.key
  end

  def test_security_sensitive_surfaces_rejects_a_blank_or_mixed_element
    cfg = base
    cfg['security'] = { 'security_contact' => '', 'security_sensitive_surfaces' => ['auth', '', 3] }
    assert_equal :error, find(cfg, :type_string_array).severity
  end

  def test_security_sensitive_surfaces_empty_array_is_fine
    cfg = base
    cfg['security'] = { 'security_contact' => '', 'security_sensitive_surfaces' => [] }
    assert_nil find(cfg, :type_string_array)
  end

  def test_security_sensitive_surfaces_good_array_is_fine
    cfg = base
    cfg['security'] = { 'security_contact' => '', 'security_sensitive_surfaces' => %w[auth payments] }
    assert_nil find(cfg, :type_string_array)
  end

  def test_security_sensitive_surfaces_present_null_fails_closed
    # A present-but-null security contract must not pass silently, exactly like
    # every other present-null invariant key. (Absent is a phase-1 missing_key.)
    cfg = base
    cfg['security'] = { 'security_contact' => '', 'security_sensitive_surfaces' => nil }
    assert_equal :error, find(cfg, :type_string_array).severity
  end

  def test_security_sensitive_surfaces_nbsp_only_element_is_blank
    cfg = base
    cfg['security'] = { 'security_contact' => '',
                        'security_sensitive_surfaces' => ["auth", "\u00A0"] }
    assert_equal :error, find(cfg, :type_string_array).severity
  end

  def test_type_error_suppresses_later_phases
    cfg = base
    cfg['issue_capture']['enabled'] = 'false'
    assert_includes check(cfg).map(&:rule), :phases_skipped
  end

  def test_non_hash_list_elements_are_skipped_not_crashed
    cfg = base
    cfg['repositories'] << 'not-a-hash'
    cfg['scheduled_jobs']['jobs'] << 'also-not-a-hash'

    assert_equal [], ConfigContract.repository_violations(cfg)
    assert_equal [], ConfigContract.job_schedule_violations(cfg)
    assert_equal [], ConfigContract.job_type_violations(cfg)
  end
end

# --- Phase 3: semantic invariants ---
class SemanticTest < Minitest::Test
  # A minimal, fully-enabled, correctly-configured config. Every semantic rule
  # is satisfied here, so each test below breaks exactly one thing.
  def base
    {
      'repositories' => [{ 'visibility' => 'private' }],
      'community' => { 'chat' => { 'monitor' => true, 'platform' => 'discord',
                                   'capture_reaction' => 'white_check_mark' } },
      'issue_capture' => {
        'enabled' => true, 'capture_marker' => 'steward-captured',
        'queue_path' => '/srv/steward/queue.md', 'ledger_path' => '/srv/steward/ledger.md',
        'checkpoint_path' => '/srv/steward/checkpoint.md',
        'max_per_run' => 10, 'max_public_files_per_run' => 0
      },
      'security' => { 'security_contact' => 'github-advisory',
                      'security_sensitive_surfaces' => ['auth'] },
      'secrets' => { 'execute_contributor_code' => false, 'sandbox_available' => false },
      'scheduled_jobs' => {
        'jobs' => [{ 'name' => 'action-watchdog', 'every' => '6h', 'enabled' => true, 'agent' => false }],
        'outputs' => { 'index_path' => '/srv/steward/index.md', 'digest_to' => '',
                       'alarms_to' => 'ops@example.com' }
      }
    }
  end

  def check(config)
    ConfigContract.check(config: config, template: base)
  end

  def rule(config, sym)
    check(config).find { |x| x.rule == sym }
  end

  def errors(config)
    check(config).select { |x| x.severity == :error }
  end

  def test_the_fully_enabled_base_has_no_errors
    assert_empty errors(base).map(&:rule)
  end

  # base with the watchdog plus `jobs`. Every job carries `agent`: base is also
  # the template here, so a job without it would not match the template's shape.
  def with_jobs(*jobs)
    cfg = base
    cfg['scheduled_jobs']['jobs'] += jobs
    cfg
  end

  def test_two_jobs_with_one_normalized_name_are_refused
    cfg = with_jobs({ 'name' => 'nightly', 'every' => '1h', 'enabled' => false, 'agent' => false },
                    { 'name' => 'Nightly ', 'every' => '2h', 'enabled' => false, 'agent' => false })
    assert rule(cfg, :job_name_unique)
  end

  def test_an_enabled_model_job_with_no_skill_is_refused
    cfg = with_jobs({ 'name' => 'mentions_sweep', 'every' => '24h', 'enabled' => true, 'agent' => true })
    assert rule(cfg, :enabled_job_needs_skill)
  end

  def test_a_deterministic_job_with_no_skill_passes
    cfg = with_jobs({ 'name' => 'fleet-heartbeat', 'cron' => '30 8 * * *', 'enabled' => true, 'agent' => false })
    assert_nil rule(cfg, :enabled_job_needs_skill)
    assert_nil rule(cfg, :phases_skipped)
  end

  def test_a_disabled_or_custom_job_is_not_checked_for_a_skill
    disabled = with_jobs({ 'name' => 'mentions-sweep', 'every' => '24h', 'enabled' => false, 'agent' => true })
    custom = with_jobs({ 'name' => 'my-own-job', 'every' => '1h', 'enabled' => true, 'agent' => true })
    [disabled, custom].each do |cfg|
      assert_nil rule(cfg, :enabled_job_needs_skill)
      assert_nil rule(cfg, :phases_skipped)
    end
  end

  def test_the_capture_job_on_with_capture_off_is_refused
    cfg = with_jobs({ 'name' => "Issue_Capture\u00A0", 'every' => '1h', 'enabled' => true, 'agent' => true })
    cfg['issue_capture']['enabled'] = false
    assert rule(cfg, :job_flag_agree)
  end

  def test_the_chat_job_on_with_monitoring_off_is_refused
    cfg = with_jobs({ 'name' => 'chat-monitor', 'every' => '1h', 'enabled' => true, 'agent' => false })
    cfg['community']['chat']['monitor'] = false
    assert rule(cfg, :job_flag_agree)
  end

  def test_the_flag_on_with_its_job_off_passes
    assert_nil rule(base, :job_flag_agree)
    assert_nil rule(base, :phases_skipped)
  end

  def test_enabled_capture_without_alarms_to_is_an_error
    cfg = base
    cfg['scheduled_jobs']['outputs']['alarms_to'] = ''
    assert_equal :error, rule(cfg, :alarms_to_required).severity
  end

  def test_whitespace_only_alarms_to_counts_as_blank
    cfg = base
    cfg['scheduled_jobs']['outputs']['alarms_to'] = '   '
    assert_equal :error, rule(cfg, :alarms_to_required).severity
  end

  def test_disabled_capture_needs_no_alarms_to
    cfg = base
    cfg['issue_capture']['enabled'] = false
    cfg['community']['chat']['monitor'] = false
    cfg['issue_capture']['capture_marker'] = ''
    cfg['scheduled_jobs']['outputs']['alarms_to'] = ''
    assert_nil rule(cfg, :alarms_to_required)
  end

  def test_enabled_capture_without_state_paths_is_an_error
    cfg = base
    cfg['issue_capture']['ledger_path'] = ''
    v = rule(cfg, :capture_state_paths_required)
    assert_equal :error, v.severity
    assert_match(/ledger_path/, v.message)
  end

  def test_repo_relative_state_path_in_a_public_repo_is_an_error
    cfg = base
    cfg['repositories'] = [{ 'visibility' => 'public' }]
    cfg['issue_capture']['ledger_path'] = 'state/ledger.md'
    v = rule(cfg, :state_paths_not_public)
    assert_equal :error, v.severity
    assert_match(/ledger_path/, v.message)
  end

  def test_enabled_capture_without_pull_index_is_an_error
    cfg = base
    cfg['scheduled_jobs']['outputs']['index_path'] = ''
    assert_equal :error, rule(cfg, :pull_index_required).severity
  end

  def test_repo_relative_index_in_a_public_repo_is_an_error
    cfg = base
    cfg['repositories'] = [{ 'visibility' => 'public' }]
    cfg['scheduled_jobs']['outputs']['index_path'] = 'state/index.md'
    assert_equal :error, rule(cfg, :index_not_public).severity
  end

  def test_mixed_visibility_still_errors_fail_closed
    cfg = base
    cfg['repositories'] = [{ 'visibility' => 'private' }, { 'visibility' => 'public' }]
    cfg['scheduled_jobs']['outputs']['index_path'] = 'state/index.md'
    assert_equal :error, rule(cfg, :index_not_public).severity
  end

  def test_no_declared_repositories_is_unknown_visibility_fail_closed
    cfg = base
    cfg['repositories'] = []
    cfg['scheduled_jobs']['outputs']['index_path'] = 'state/index.md'
    assert_equal :error, rule(cfg, :index_not_public).severity
  end

  def test_repo_relative_index_in_a_private_repo_is_fine
    cfg = base
    cfg['scheduled_jobs']['outputs']['index_path'] = 'state/index.md'
    assert_nil rule(cfg, :index_not_public)
  end

  def test_repo_relative_state_path_in_a_private_repo_is_fine
    cfg = base
    cfg['issue_capture']['ledger_path'] = 'state/ledger.md'
    assert_nil rule(cfg, :state_paths_not_public)
  end

  def test_public_repo_index_with_capture_disabled_is_fine
    cfg = base
    cfg['repositories'] = [{ 'visibility' => 'public' }]
    cfg['issue_capture']['enabled'] = false
    cfg['community']['chat']['monitor'] = false
    cfg['issue_capture']['capture_marker'] = ''
    cfg['scheduled_jobs']['outputs']['index_path'] = 'state/index.md'
    assert_nil rule(cfg, :index_not_public)
  end

  def test_marker_without_enabled_watchdog_is_an_error
    cfg = base
    cfg['scheduled_jobs']['jobs'][0]['enabled'] = false
    assert_equal :error, rule(cfg, :marker_needs_watchdog).severity
  end

  def test_marker_with_no_watchdog_job_at_all_is_an_error
    cfg = base
    cfg['scheduled_jobs']['jobs'] = [{ 'name' => 'label-sync', 'every' => '4h', 'enabled' => true, 'agent' => false }]
    assert_equal :error, rule(cfg, :marker_needs_watchdog).severity
  end

  def test_reaction_with_monitor_and_no_watchdog_is_an_error
    cfg = base
    cfg['issue_capture']['capture_marker'] = ''
    cfg['scheduled_jobs']['jobs'][0]['enabled'] = false
    assert_equal :error, rule(cfg, :reaction_needs_watchdog).severity
  end

  def test_monitor_without_capture_core_is_an_error
    cfg = base
    cfg['issue_capture']['enabled'] = false
    assert_equal :error, rule(cfg, :chat_needs_capture_core).severity
  end

  def test_monitor_without_platform_is_an_error
    cfg = base
    cfg['community']['chat']['platform'] = ''
    assert_equal :error, rule(cfg, :chat_needs_platform).severity
    assert_nil rule(cfg, :phases_skipped),
              'phase 3 ran and found this fault — it must not also claim it never ran'
  end

  def test_public_filing_without_watchdog_is_an_error
    cfg = base
    cfg['issue_capture']['capture_marker'] = ''
    cfg['community']['chat']['capture_reaction'] = ''
    cfg['issue_capture']['max_public_files_per_run'] = 3
    cfg['scheduled_jobs']['jobs'][0]['enabled'] = false
    assert_equal :error, rule(cfg, :public_files_need_watchdog).severity
  end

  def test_contributor_code_without_sandbox_is_an_error
    cfg = base
    cfg['secrets']['execute_contributor_code'] = true
    assert_equal :error, rule(cfg, :sandbox_required).severity
  end

  def test_undecidable_destinations_warn_once_and_do_not_error
    cfg = base
    cfg['scheduled_jobs']['outputs']['digest_to'] = '#steward-digest'
    v = check(cfg)
    warnings = v.select { |x| x.rule == :destinations_unverifiable }
    assert_equal 1, warnings.size
    assert_equal :warning, warnings.first.severity
    assert_match(/index_path/, warnings.first.message)
    assert_match(/digest_to/, warnings.first.message)
    assert_empty v.select { |x| x.severity == :error }
  end

  def test_no_unverifiable_warning_when_capture_is_disabled
    cfg = base
    cfg['issue_capture']['enabled'] = false
    cfg['community']['chat']['monitor'] = false
    cfg['issue_capture']['capture_marker'] = ''
    assert_nil rule(cfg, :destinations_unverifiable)
  end

  # --- Fix: traversal is outside the repo, not repo-relative (privacy fail-open) ---
  def test_dotdot_escaped_index_is_not_repo_relative_and_warns
    cfg = base
    cfg['scheduled_jobs']['outputs']['index_path'] = '../public-site/vulns.md'
    # No index_not_public error even in an all-private declaration…
    assert_nil rule(cfg, :index_not_public)
    # …but it is routed to the unverifiable warning as outside-the-repo.
    w = rule(cfg, :destinations_unverifiable)
    refute_nil w
    assert_match(%r{index_path '\.\./public-site/vulns\.md'}, w.message)
  end

  def test_dotdot_escaped_index_in_a_public_repo_still_does_not_false_error
    cfg = base
    cfg['repositories'] = [{ 'visibility' => 'public' }]
    cfg['scheduled_jobs']['outputs']['index_path'] = '../elsewhere/index.md'
    # Outside the repo → undecidable, handled by the warning, not index_not_public.
    assert_nil rule(cfg, :index_not_public)
  end

  def test_plain_repo_relative_index_is_still_repo_relative
    cfg = base
    cfg['repositories'] = [{ 'visibility' => 'public' }]
    cfg['scheduled_jobs']['outputs']['index_path'] = 'state/index.md'
    assert_equal :error, rule(cfg, :index_not_public).severity
  end

  # --- Fix: an enabled watchdog with a blank schedule provides no coverage ---
  # A blank schedule is itself a phase-1 error (job_schedule_blank), which
  # fail-closes phase 3. So the observable guarantee is: the config does NOT pass,
  # and the semantic watchdog rules never get a chance to be fooled into passing.
  def test_blank_scheduled_watchdog_fails_closed_before_semantics
    cfg = base
    cfg['scheduled_jobs']['jobs'][0]['every'] = ''
    r = check(cfg).map(&:rule)
    assert_includes r, :job_schedule_blank
    assert_includes r, :phases_skipped
  end

  # Direct proof at the helper level: a blank-scheduled watchdog is not counted
  # as coverage, so if phase 1 ever let it through, the marker rule would fire.
  def test_watchdog_enabled_ignores_a_blank_scheduled_watchdog
    cfg = base
    cfg['scheduled_jobs']['jobs'][0]['every'] = ''
    refute ConfigContract.watchdog_enabled?(cfg),
           'an unschedulable watchdog must not count as watchdog coverage'
  end

  # --- Fix: unverifiable warning is exhaustive (security_contact + absolute state) ---
  def test_non_sentinel_security_contact_appears_in_the_warning
    cfg = base
    cfg['security']['security_contact'] = '#security-team'
    w = rule(cfg, :destinations_unverifiable)
    refute_nil w
    assert_match(/security_contact '#security-team'/, w.message)
  end

  def test_github_advisory_sentinel_is_not_listed_as_unverifiable
    cfg = base
    # base already uses the sentinel; only the always-outside index should list.
    w = rule(cfg, :destinations_unverifiable)
    refute_nil w
    refute_match(/security_contact/, w.message)
  end

  def test_absolute_state_paths_appear_in_the_warning
    cfg = base
    w = rule(cfg, :destinations_unverifiable)
    refute_nil w
    assert_match(%r{issue_capture\.queue_path '/srv/steward/queue\.md'}, w.message)
  end

  # --- Fix: alarms_to must be an independent route ---
  def test_alarms_to_equal_to_index_path_is_not_independent
    cfg = base
    cfg['scheduled_jobs']['outputs']['alarms_to'] = cfg['scheduled_jobs']['outputs']['index_path']
    assert_equal :error, rule(cfg, :alarms_to_independent).severity
  end

  def test_alarms_to_equal_to_security_contact_is_not_independent
    cfg = base
    cfg['security']['security_contact'] = 'ops@example.com'
    cfg['scheduled_jobs']['outputs']['alarms_to'] = 'ops@example.com'
    assert_equal :error, rule(cfg, :alarms_to_independent).severity
  end

  def test_alarms_to_equal_to_a_state_path_is_not_independent
    cfg = base
    cfg['scheduled_jobs']['outputs']['alarms_to'] = cfg['issue_capture']['ledger_path']
    assert_equal :error, rule(cfg, :alarms_to_independent).severity
  end

  def test_alarms_to_nbsp_padded_duplicate_of_security_contact_is_not_independent
    # A Unicode-whitespace-padded duplicate must not dodge the independence rule
    # the way an ASCII String#strip comparison would let it (round-2 gate finding).
    cfg = base
    cfg['security']['security_contact'] = 'ops@example.com'
    cfg['scheduled_jobs']['outputs']['alarms_to'] = "\u00A0ops@example.com\u00A0"
    assert_equal :error, rule(cfg, :alarms_to_independent).severity
  end

  def test_an_independent_alarms_to_is_fine
    # base's alarms_to (ops@example.com) differs from every other destination.
    assert_nil rule(base, :alarms_to_independent)
  end

  # The whole design rests on phase 1/2 errors suppressing phase 3. Prove it
  # directly: a config that would trip index_not_public AND carries a type
  # error must report the type error and phases_skipped, never the semantic
  # rule the type error masked.
  def test_a_type_error_suppresses_a_semantic_rule_that_would_otherwise_fire
    cfg = base
    cfg['repositories'] = [{ 'visibility' => 'public' }]
    cfg['scheduled_jobs']['outputs']['index_path'] = 'state/index.md'
    cfg['secrets']['execute_contributor_code'] = 'yes'

    rules = check(cfg).map(&:rule)
    assert_includes rules, :type_boolean
    assert_includes rules, :phases_skipped
    refute_includes rules, :index_not_public
  end

  # --- Safe escape hatches ---
  #
  # Four rules fire on `precondition && !remedy`. The reds prove they fire when
  # the remedy is absent; the green never reaches the precondition at all. So
  # nothing otherwise pins the corner where the precondition IS met and the
  # adopter HAS applied the remedy the message tells them to apply.
  #
  # The two privacy rules (index_not_public, state_paths_not_public) get one
  # test per conjunct, not one test total: the absolute-path test pins
  # repo_relative?, the private-repo test pins public_repo?. A single test
  # can't pin both, because an absolute path short-circuits the `&&` before
  # public_repo? is ever evaluated. Don't consolidate these back to one test
  # each — that asymmetry is exactly why there are two.
  #
  # assert_nil passes trivially whenever the rule fails to fire for any
  # reason at all, so each assertion here is mutation-confirmed: drop any one
  # of the four conjuncts across these rules and exactly one test below fails.
  #
  # This is the fail-closed direction, so it leaks nothing. It blocks every
  # correctly-configured adopter instead, which is the failure this corpus is
  # supposed to make impossible to ship unnoticed.

  def test_public_filing_with_an_enabled_watchdog_is_fine
    cfg = base
    cfg['issue_capture']['max_public_files_per_run'] = 3
    assert_nil rule(cfg, :public_files_need_watchdog)
  end

  def test_contributor_code_with_a_sandbox_is_fine
    cfg = base
    cfg['secrets']['execute_contributor_code'] = true
    cfg['secrets']['sandbox_available'] = true
    assert_nil rule(cfg, :sandbox_required)
  end

  def test_absolute_index_path_in_a_public_repo_is_fine
    cfg = base
    cfg['repositories'][0]['visibility'] = 'public'
    cfg['scheduled_jobs']['outputs']['index_path'] = '/var/steward/index.md'
    assert_nil rule(cfg, :index_not_public)
  end

  def test_absolute_state_paths_in_a_public_repo_is_fine
    cfg = base
    cfg['repositories'][0]['visibility'] = 'public'
    assert_nil rule(cfg, :state_paths_not_public)
  end
end

# --- Entrypoint: the real bin, not just the helpers ---
class EntrypointTest < Minitest::Test
  BIN = File.expand_path('../bin/config-lint', __dir__)

  def run_lint(*args)
    out = IO.popen([BIN, *args], err: [:child, :out], &:read)
    [out, $CHILD_STATUS.exitstatus]
  end

  def test_no_args_checks_both_in_repo_configs_and_passes
    out, status = run_lint
    assert_equal 0, status, out
    assert_match(/config\.template\.yaml/, out)
    assert_match(/setup\/config\.yaml/, out)
    assert_match(/OK/, out)
  end

  def test_help_states_the_boundary
    out, status = run_lint('--help')
    assert_equal 0, status
    assert_match(/statically decidable subset/, out)
    assert_match(/does not replace/, out)
  end

  def test_unreadable_path_exits_1_rather_than_crashing
    out, status = run_lint('no/such/config.yaml')
    assert_equal 1, status
    assert_match(/could not read/, out)
  end

  def test_a_parse_violation_prints_its_rule_and_skips_the_phases
    out, status = run_lint(File.join(FIXTURE_ROOT, 'red-duplicate_key.yaml'))
    assert_equal 1, status
    assert_match(/red-duplicate_key\.yaml — 1 error\(s\), 0 warning\(s\)/, out)
    assert_match(/repositories/, out)
    assert_match(/NOT evaluated/, out)
  end

  def test_a_template_with_a_parse_violation_fails_the_run
    Dir.mktmpdir do |dir|
      root = File.expand_path('..', __dir__)
      %w[bin lib setup].each { |d| FileUtils.cp_r(File.join(root, d), dir) }
      File.open(File.join(dir, 'setup', 'config.template.yaml'), 'a') { |f| f.puts 'repositories: []' }
      out, status = run_in(dir)
      assert_equal 1, status, out
      assert_match(/config\.template\.yaml/, out)
      assert_match(/repositories/, out)
    end
  end

  # Runs the copy of bin/config-lint under `dir` with no arguments.
  def run_in(dir)
    out = IO.popen([File.join(dir, 'bin', 'config-lint')], err: [:child, :out], &:read)
    [out, $CHILD_STATUS.exitstatus]
  end
end

# --- Corpus: every rule has a fixture that provokes it ---
class CorpusTest < Minitest::Test
  BIN = File.expand_path('../bin/config-lint', __dir__)

  def self.red_fixtures
    Dir.glob(File.join(FIXTURE_ROOT, 'red-*.yaml')).sort
  end

  def rules_for(path)
    template = ConfigContract::Extract.load(
      File.expand_path('../setup/config.template.yaml', __dir__)
    )
    ConfigContract.check_file(path, template: template)
                  .select { |v| v.severity == :error }.map(&:rule)
  end

  def test_the_corpus_is_not_empty
    floor = ConfigContract::SEMANTIC_RULES.size + ConfigContract::PARSE_RULES.size + 4
    assert_operator self.class.red_fixtures.size, :>=, floor,
                    'red fixtures went missing — the corpus proves nothing if it does not load'
  end

  def test_green_fixture_passes_through_the_real_entrypoint
    out = IO.popen([BIN, File.join(FIXTURE_ROOT, 'green-enabled.yaml')], err: [:child, :out], &:read)
    assert_equal 0, $CHILD_STATUS.exitstatus, out
  end

  red_fixtures.each do |path|
    name = File.basename(path, '.yaml')
    expected = name.sub(/\Ared-/, '').to_sym

    define_method("test_#{name}_provokes_#{expected}") do
      actual = rules_for(path)
      assert_includes actual, expected,
                      "#{name} did not provoke #{expected} — got #{actual.inspect}"
    end

    define_method("test_#{name}_exits_nonzero") do
      IO.popen([BIN, path], err: [:child, :out], &:read)
      assert_equal 1, $CHILD_STATUS.exitstatus
    end
  end
end

# --- JOB_SKILLS stays in step with the template and skills/ ---
class JobSkillsMapTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def template_job_names
    ConfigContract::Extract.load(File.join(ROOT, 'setup/config.template.yaml'))
                  .dig('scheduled_jobs', 'jobs').map { |j| j['name'] }
  end

  def test_the_map_covers_exactly_the_template_jobs
    assert_equal template_job_names.sort, ConfigContract::JOB_SKILLS.keys.sort
  end

  def test_every_mapped_skill_exists
    ConfigContract::JOB_SKILLS.values.compact.each do |skill|
      assert File.directory?(File.join(ROOT, 'skills', skill)), "skills/#{skill} is missing"
    end
  end

  def test_a_job_mapped_to_no_skill_really_has_none
    ConfigContract::JOB_SKILLS.select { |_, skill| skill.nil? }.each_key do |job|
      refute File.directory?(File.join(ROOT, 'skills', job)),
             "skills/#{job} now exists: map it in JOB_SKILLS"
    end
  end
end

# --- Anti-vacuity: a rule with no fixture fails the suite ---
class MetaTest < Minitest::Test
  def test_every_semantic_and_parse_rule_has_a_red_fixture
    covered = Dir.glob(File.join(FIXTURE_ROOT, 'red-*.yaml'))
                 .map { |p| File.basename(p, '.yaml').sub(/\Ared-/, '').to_sym }
    missing = (ConfigContract::SEMANTIC_RULES + ConfigContract::PARSE_RULES) - covered
    assert_empty missing,
                 "these rules have no red fixture, so nothing proves they fire: #{missing.inspect}"
  end
end
