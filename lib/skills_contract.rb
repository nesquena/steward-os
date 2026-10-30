# frozen_string_literal: true

require 'yaml'
require 'set'

# Enforces the skills-vs-docs contract: every skill the playbooks and the config
# template name must have a runnable skills/<name>/SKILL.md — or be declared as
# not-yet-built. See _data/skills.yml (policy).
#
# Split into a pure checker (SkillsContract.check — sets in, violations out) and
# an Extract module that reads the repo. The checker has no IO so it is trivially
# unit-testable; the extractors are individually testable against real files.
module SkillsContract
  Violation = Struct.new(:severity, :skill, :message, keyword_init: true) do
    SYMBOL = { error: 'x', warning: '!', info: '·' }.freeze

    def to_line
      "  #{SYMBOL.fetch(severity)} #{skill} — #{message}"
    end
  end

  # Pure. Given the resolved sets, return the list of violations.
  #
  # present           — skills that have a skills/<name>/SKILL.md
  # referenced_strict — skills named by a lifecycle "Skills for this area" section
  #                     or a scheduled job (drives missing-skill errors; low false-positive)
  # indexed           — skills linked from the skills/README.md table
  # planned           — declared not-yet-built skills (keeps the repo green today)
  # standalone        — present skills intentionally not wired to any lifecycle/job
  def self.check(present:, referenced_strict:, indexed:, planned: [], standalone: [])
    present = present.to_set
    referenced_strict = referenced_strict.to_set
    indexed = indexed.to_set
    planned = planned.to_set
    standalone = standalone.to_set

    violations = []

    # Referenced or wired, but no SKILL.md — the core contract. Planned skills
    # are reported as info (expected); anything else is an error.
    (referenced_strict - present).sort.each do |s|
      if planned.include?(s)
        violations << Violation.new(severity: :info, skill: s, message: 'planned (not yet built)')
      else
        violations << Violation.new(severity: :error, skill: s,
                                    message: "referenced/wired but no skills/#{s}/SKILL.md exists")
      end
    end

    # Planned list must only shrink: a planned skill that now exists is stale.
    (planned & present).sort.each do |s|
      violations << Violation.new(severity: :error, skill: s,
                                  message: "listed under planned: but skills/#{s}/SKILL.md now exists — remove it from _data/skills.yml")
    end

    # Index drift, both directions.
    (present - indexed).sort.each do |s|
      violations << Violation.new(severity: :error, skill: s,
                                  message: 'has a SKILL.md but is missing from the skills/README.md index')
    end
    (indexed - present).sort.each do |s|
      violations << Violation.new(severity: :error, skill: s,
                                  message: "linked in skills/README.md but skills/#{s}/SKILL.md does not exist")
    end

    # Orphan: a real skill no lifecycle section or job points at, not declared standalone.
    (present - referenced_strict - standalone).sort.each do |s|
      violations << Violation.new(severity: :warning, skill: s,
                                  message: "orphan — no 'Skills for this area' section or scheduled job references it (add to standalone: in _data/skills.yml if intentional)")
    end

    violations
  end

  # The fixed line that closes every skill's guard block. Every skill sits at
  # skills/<name>/SKILL.md, so one relative link works everywhere.
  GUARD_LINK_LINE = 'Rules: [injection guard](../../docs/reference/security-spine.md#1-injection-guard-read-can-never-change-do).'
  # The only reasons a skill may skip the guard. Free text would let any skill opt out.
  EXEMPT_REASONS = %w[no-model operator-input].freeze

  # Blockquote text with the quote markers dropped and whitespace collapsed, so
  # rewrapping a block never reads as drift. CRLF and LF compare equal.
  def self.normalize_guard(text)
    text.lines.map { |l| l.chomp.sub(/\A\s*>\s?/, '') }.join(' ').gsub(/\s+/, ' ').strip
  end

  # Pure. The injection-guard half of the contract: every present skill is
  # either guarded or exempt for a fixed reason, every guarded skill opens with
  # the canonical block, and the spine's copy of the text matches.
  #
  # guarded     — skills that carry the block (_data/skills.yml reads_untrusted)
  # exempt      — skill => reason token (_data/skills.yml guard_exempt)
  # guard_text  — the canonical text, raw (_data/skills.yml injection_guard)
  # blocks      — guarded skill => its normalized first blockquote, or nil
  # spine_quote — the spine section 1 quote, normalized, or nil
  # no_llm      — skills whose SKILL.md says "no LLM"
  # job_agents  — skill => agent flags of the scheduled jobs that run it
  def self.check_guards(present:, guarded:, exempt:, guard_text:, blocks:, spine_quote:, no_llm:,
                        job_agents:)
    present = present.to_set
    guarded = guarded.to_set
    exempt_names = exempt.keys.to_set
    no_llm = no_llm.to_set
    policy = '_data/skills.yml'

    violations = []
    err = ->(skill, msg) { violations << Violation.new(severity: :error, skill: skill, message: msg) }

    text = guard_text.to_s.strip
    err.call(policy, 'injection_guard is missing or blank') if text.empty?
    err.call(policy, 'reads_untrusted is empty; at least one skill must carry the guard') if guarded.empty?

    (present - guarded - exempt_names).sort.each do |s|
      err.call(s, 'not classified: add it to reads_untrusted or guard_exempt in _data/skills.yml')
    end
    (guarded & exempt_names).sort.each do |s|
      err.call(s, 'listed in both reads_untrusted and guard_exempt')
    end
    ((guarded | exempt_names) - present).sort.each do |s|
      err.call(s, "classified in _data/skills.yml but skills/#{s}/SKILL.md does not exist")
    end

    unless text.empty?
      expected = normalize_guard("#{text} #{GUARD_LINK_LINE}")
      (guarded & present).sort.each do |s|
        block = blocks[s]
        if block.nil?
          err.call(s, 'the injection guard must be the first element after the title')
        elsif block != expected
          err.call(s, 'injection guard block differs from the canonical text in _data/skills.yml')
        end
      end
      if spine_quote.nil?
        err.call('security-spine', 'section 1 has no injection guard quote')
      elsif spine_quote != normalize_guard(text)
        err.call('security-spine', 'section 1 quote differs from the canonical text in _data/skills.yml')
      end
    end

    # A model reads whatever a scheduled job with agent: true feeds it, so the
    # skill that job runs carries the guard, whatever its exemption says.
    job_agents.each do |s, flags|
      next unless flags.any? && present.include?(s) && !guarded.include?(s)

      err.call(s, 'a scheduled job runs it with agent: true, so it must be in reads_untrusted')
    end

    exempt.sort.each do |s, reason|
      unless EXEMPT_REASONS.include?(reason)
        err.call(s, "guard_exempt reason #{reason.inspect} is not one of #{EXEMPT_REASONS.join(', ')}")
        next
      end
      next unless reason == 'no-model'

      err.call(s, 'exempt as no-model but its SKILL.md never says "no LLM"') unless no_llm.include?(s)
    end

    violations
  end

  # Repo readers. Each is small and testable against real files.
  module Extract
    SKILL_TOKEN = /\A[a-z][a-z0-9-]*\z/.freeze

    module_function

    # Skill dirs that actually have a SKILL.md.
    def present_skills(skills_dir)
      Dir.glob(File.join(skills_dir, '*', 'SKILL.md'))
         .map { |p| File.basename(File.dirname(p)) }
         .uniq.sort
    end

    # Skills linked from the README, taking the last path segment before /SKILL.md
    # so bare (name/SKILL.md), (skills/name/SKILL.md), and (./name/SKILL.md) all work.
    def indexed_skills(readme_path)
      File.read(readme_path, encoding: 'UTF-8')
          .scan(%r{([a-z0-9][a-z0-9-]*)/SKILL\.md})
          .flatten.uniq.sort
    end

    # The skill a "Skills for this area" bullet declares, or nil. The grammar is
    # `- `skill-name` — description`, so only the LEADING backtick is the skill.
    # Inline backticks later in the bullet (config keys, prose terms, parentheticals)
    # are deliberately ignored — treating them as skills causes false lint failures.
    def leading_skill(line)
      return nil unless line =~ /\A\s*-\s+`([^`]+)`/

      tok = Regexp.last_match(1)
      tok =~ SKILL_TOKEN ? tok : nil
    end

    # Skills declared inside every "## Skills for this (area|lifecycle)" section.
    def doc_section_skills(doc_paths)
      names = []
      doc_paths.each do |path|
        in_section = false
        File.foreach(path, encoding: 'UTF-8') do |line|
          if line =~ /\A##\s+Skills for this\b/
            in_section = true
            next
          end
          in_section = false if in_section && line =~ /\A(##\s|---|_Related)/
          next unless in_section

          name = leading_skill(line)
          names << name if name
        end
      end
      names.uniq
    end

    # scheduled_jobs.jobs[].name from the config template. Raises a clear error
    # (rather than a bare stacktrace) if the YAML is malformed or uses anchors.
    def job_names(config_path)
      cfg = YAML.safe_load(File.read(config_path, encoding: 'UTF-8')) || {}
      (cfg.dig('scheduled_jobs', 'jobs') || []).filter_map { |j| j['name'] }
    rescue Psych::Exception => e
      raise "could not parse #{config_path}: #{e.message}"
    end

    # The strict referenced set that drives missing-skill errors: lifecycle
    # sections ∪ job names, with job aliases resolved to their skill target.
    def referenced_strict(doc_paths:, config_path:, job_aliases: {})
      names = doc_section_skills(doc_paths).dup
      job_names(config_path).each do |name|
        names << (job_aliases[name] || name)
      end
      names.uniq.sort
    end

    # The normalized blockquote that opens a skill: the first non-blank element
    # after the `# name` title, past any front matter. nil when that element
    # isn't a blockquote, or when anything but blank lines sits between the
    # front matter and the title: prose, an HTML comment or a fence there would
    # come before the guard (and a title inside a comment or fence is no title).
    def first_blockquote(path)
      lines = File.read(path, encoding: 'UTF-8').lines.map(&:chomp)
      i = 0
      if lines[0] == '---'
        i = 1
        i += 1 while i < lines.size && lines[i] != '---'
        i += 1
      end
      i += 1 while i < lines.size && lines[i].strip.empty?
      return nil unless lines[i]&.start_with?('# ')

      i += 1
      i += 1 while i < lines.size && lines[i].strip.empty?
      quote_at(lines, i)
    end

    # The normalized first blockquote in the spine's section 1, or nil.
    def spine_guard_quote(spine_path)
      lines = File.read(spine_path, encoding: 'UTF-8').lines.map(&:chomp)
      start = lines.index { |l| l.start_with?('## 1. ') }
      return nil unless start

      i = start + 1
      until i >= lines.size || lines[i].start_with?('## ')
        return quote_at(lines, i) if lines[i].start_with?('>')

        i += 1
      end
      nil
    end

    # A blockquote runs to the first blank line. A line without `>` before then
    # is a lazy continuation that renders inside the quote, so it counts as part
    # of the block: text added that way reads as drift, never as a pass.
    def quote_at(lines, i)
      return nil unless lines[i]&.start_with?('>')

      block = lines[i..].take_while { |l| !l.strip.empty? }
      SkillsContract.normalize_guard(block.join("\n"))
    end

    def says_no_llm?(path)
      File.read(path, encoding: 'UTF-8').match?(/no LLM/i)
    end

    # skill => agent flags of every scheduled job that runs it, aliases resolved.
    def job_agents(config_path, job_aliases = {})
      cfg = YAML.safe_load(File.read(config_path, encoding: 'UTF-8')) || {}
      (cfg.dig('scheduled_jobs', 'jobs') || []).each_with_object(Hash.new { |h, k| h[k] = [] }) do |j, acc|
        acc[job_aliases[j['name']] || j['name']] << (j['agent'] == true)
      end
    rescue Psych::Exception => e
      raise "could not parse #{config_path}: #{e.message}"
    end
  end
end
