# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/anchor_contract'

# --- Heading ids: the anchors the renderer actually emits ---
#
# These assert the whole extraction path, not a slugger helper. The ids below
# were read off real pages in _site/; they are the contract the cross-references
# in docs/ depend on, and they hold because extraction asks kramdown-parser-gfm
# rather than predicting.
class HeadingIdsTest < Minitest::Test
  def ids(text) = AnchorContract::Extract.heading_ids(text)

  def id_for(heading) = ids("## #{heading}\n").first

  def test_plain_heading
    assert_equal 'the-pipeline-at-a-glance', id_for('The pipeline at a glance')
  end

  # The regression guard: kramdown's native slugger strips the leading digit and
  # would return 'fit--scope-screen'. Four live cross-references depend on this id.
  def test_leading_bracket_number_is_kept
    assert_equal '0-fit--scope-screen', id_for('[0] Fit / scope screen')
  end

  def test_em_dash_and_ampersand_collapse_to_double_hyphens
    assert_equal 'section-1--identity--repositories-required',
                 id_for('Section 1 — Identity & repositories *(required)*')
  end

  def test_arrow_and_parentheses
    assert_equal 'confidence-tiered-capture--action-the-safe-way-to-auto-file',
                 id_for('Confidence-tiered capture → action (the safe way to auto-file)')
  end

  def test_code_span_reduces_to_its_text
    assert_equal 'the-issue-capture-skill', id_for('The `issue-capture` skill')
  end

  def test_link_reduces_to_its_text
    assert_equal 'see-the-glossary', id_for('See [the glossary](glossary.md)')
  end

  def test_underscore_emphasis_reduces_to_its_text
    assert_equal 'a-strong-claim', id_for('A _strong_ claim')
  end

  def test_html_tags_are_stripped_to_their_text
    assert_equal 'a-bold-heading', id_for('A <em>bold</em> heading')
  end

  def test_html_entities_are_decoded
    assert_equal 'fish--chips', id_for('Fish &amp; Chips')
  end

  def test_escaped_underscore_stays_literal_and_is_not_emphasis
    assert_equal 'a-_literal_-thing', id_for('A \_literal\_ thing')
  end

  def test_collects_all_levels_in_document_order
    md = "# Title\n\ntext\n\n## First\n\n### Nested\n"
    assert_equal %w[title first nested], ids(md)
  end

  def test_ignores_headings_inside_fenced_code
    md = "# Real\n\n```\n# Fake\n```\n\n## Also real\n"
    assert_equal %w[real also-real], ids(md)
  end

  def test_ignores_headings_inside_tilde_fences
    md = "# Real\n\n~~~\n# Fake\n~~~\n"
    assert_equal %w[real], ids(md)
  end

  def test_ignores_hash_that_is_not_a_heading
    md = "# Real\n\nsee #4 for context\n"
    assert_equal %w[real], ids(md)
  end

  def test_duplicate_headings_get_a_counter_suffix
    md = "## Notes\n\n## Notes\n\n## Notes\n"
    assert_equal %w[notes notes-1 notes-2], ids(md)
  end

  def test_trailing_closing_hashes_are_stripped
    assert_equal %w[title], ids("# Title #\n")
  end

  # What the site emits. GitHub emits something else, so UnportableTest rejects
  # the document before any of these ids is trusted — see Extract.unportable.
  def test_explicit_custom_id_is_used_verbatim
    assert_equal %w[my-id], ids("## Some heading {#my-id}\n")
  end

  # A four-backtick fence must not be closed by an inner three-backtick line, or
  # headings in the example get invented as real ids.
  def test_longer_fence_is_not_closed_by_a_shorter_inner_fence
    md = "# Real\n\n````\n```\n# Fake\n```\n````\n\n## Also real\n"
    assert_equal %w[real also-real], ids(md)
  end

  # --- Cases a predicted slug got wrong. Each id here is what the page emits. ---

  # `__x__` is strong emphasis, not literal underscores.
  def test_double_underscore_strong_reduces_to_its_text
    assert_equal %w[strong], ids("## __Strong__\n")
  end

  def test_reference_link_heading_drops_the_label
    md = "## [Reference heading][ref]\n\n[ref]: https://example.com\n"
    assert_equal %w[reference-heading], ids(md)
  end

  # A block IAL on the following line overrides the automatic slug — on the site.
  # Rejected as unportable for the same reason as the brace form above.
  def test_block_attribute_id_overrides_the_automatic_slug
    assert_equal %w[my-id], ids("## Auto slug\n{: #my-id}\n")
  end

  # Two explicit ids collide verbatim — the renderer does not disambiguate them,
  # so there is no `same-1` anchor to link to.
  def test_repeated_explicit_ids_are_not_counter_suffixed
    md = "## Same {#same}\n\ntext\n\n## Same again {#same}\n"
    assert_equal %w[same same], ids(md)
  end

  # Setext underlines are headings on both renderers.
  def test_setext_headings_are_emitted
    assert_equal %w[underlined-heading], ids("Underlined heading\n==================\n")
  end

  # Jekyll removes front matter before rendering and GitHub shows it as a table,
  # so a `#` line inside it is an anchor on neither.
  def test_front_matter_is_not_scanned_for_headings
    md = "---\nlayout: default\n# phantom-anchor\n---\n\n## Real\n"
    assert_equal %w[real], ids(md)
  end

  # Jekyll's regex ends `$\n?`, so front matter may close at EOF. Requiring the
  # newline left the block unstripped and turned its `#` lines into anchors.
  def test_front_matter_closing_at_eof_is_still_stripped
    assert_empty ids("---\ntitle: x\n# phantom-anchor\n---")
  end

  def test_front_matter_closing_with_dots_at_eof_is_still_stripped
    assert_empty ids("---\ntitle: x\n# phantom-anchor\n...")
  end

  def test_front_matter_blanking_preserves_line_numbers
    md = "---\ntitle: x\n---\n\n[gates](quality-gates.md)\n"
    link = AnchorContract::Extract.links(md, source: 'index.md').first
    assert_equal 5, link.line
  end
end

# --- Link extraction: repo-relative resolution, externals skipped ---
class LinksTest < Minitest::Test
  def links(text, source: 'docs/lifecycle/pr-lifecycle.md')
    AnchorContract::Extract.links(text, source: source)
  end

  def paths(text, **opts) = links(text, **opts).map(&:path)

  def test_extracts_a_sibling_link
    l = links("see [gates](quality-gates.md) now\n").first
    assert_equal 'docs/lifecycle/quality-gates.md', l.path
    assert_nil l.fragment
    assert_equal 1, l.line
  end

  def test_resolves_parent_relative_paths
    l = links("see [glossary](../reference/glossary.md#fit-screen)\n").first
    assert_equal 'docs/reference/glossary.md', l.path
    assert_equal 'fit-screen', l.fragment
  end

  def test_same_file_fragment_has_empty_path
    l = links("jump to [routing](#2-routing)\n").first
    assert_equal '', l.path
    assert_equal '2-routing', l.fragment
  end

  def test_skips_external_and_absolute_links
    md = "[a](https://example.com) [b](mailto:x@y.z) [c](/root/abs.md)\n"
    assert_empty links(md)
  end

  def test_skips_links_inside_fenced_code
    md = "```\n[fake](nope.md)\n```\n\n[real](quality-gates.md)\n"
    assert_equal %w[docs/lifecycle/quality-gates.md], paths(md)
  end

  def test_finds_a_link_whose_text_wraps_across_lines
    md = "prose [the authoritative\ngate](quality-gates.md) more prose\n"
    l = links(md).first
    assert_equal 'docs/lifecycle/quality-gates.md', l.path
    assert_equal 1, l.line
  end

  def test_reports_the_line_of_a_later_link
    md = "line one\n\nsee [gates](quality-gates.md)\n"
    assert_equal 3, links(md).first.line
  end

  def test_resolves_a_link_from_a_root_level_file
    l = links("see [quickstart](quickstart.md)\n", source: 'index.md').first
    assert_equal 'quickstart.md', l.path
  end

  def test_extracts_a_link_that_carries_a_title
    l = links(%(see [gates](quality-gates.md "the gates") now\n)).first
    assert_equal 'docs/lifecycle/quality-gates.md', l.path
  end

  def test_extracts_an_angle_bracketed_target
    l = links("see [gates](<quality-gates.md>)\n").first
    assert_equal 'docs/lifecycle/quality-gates.md', l.path
  end

  def test_extracts_a_reference_style_link
    l = links("see [gates][g]\n\n[g]: quality-gates.md\n").first
    assert_equal 'docs/lifecycle/quality-gates.md', l.path
  end

  def test_skips_an_external_reference_definition
    assert_empty links("see [home][h]\n\n[h]: https://example.com\n")
  end

  def test_skips_a_link_inside_a_longer_fence_holding_an_inner_fence
    md = "````\n```\n[fake](nope.md)\n```\n````\n\n[real](quality-gates.md)\n"
    assert_equal %w[docs/lifecycle/quality-gates.md], paths(md)
  end

  def test_extracts_an_image_target
    assert_equal %w[docs/lifecycle/diagram.svg], paths("![flow](diagram.svg)\n")
  end

  def test_extracts_a_raw_html_link
    assert_equal %w[docs/lifecycle/quality-gates.md], paths(%(<a href="quality-gates.md">gates</a>\n))
  end

  # --- Forms a regex grammar dropped. Each renders as a link on the page. ---

  def test_extracts_a_link_whose_text_holds_brackets
    assert_equal %w[docs/lifecycle/quality-gates.md], paths('[nested [label]](quality-gates.md)')
  end

  def test_extracts_a_link_whose_text_holds_an_escaped_bracket
    assert_equal %w[docs/lifecycle/quality-gates.md], paths('[escaped \] label](quality-gates.md)')
  end

  # The old grammar matched the inner image and lost the wrapping link entirely.
  def test_extracts_both_targets_of_an_image_wrapped_link
    md = '[![badge](badge.svg)](quality-gates.md)'
    assert_equal %w[docs/lifecycle/badge.svg docs/lifecycle/quality-gates.md], paths(md).sort
  end

  def test_extracts_a_link_whose_title_holds_escaped_quotes
    md = '[x](quality-gates.md "a \"quoted\" title")'
    assert_equal %w[docs/lifecycle/quality-gates.md], paths(md)
  end

  def test_extracts_a_target_holding_balanced_parentheses
    assert_equal %w[docs/lifecycle/notes(draft).md], paths('[x](notes(draft).md)')
  end

  # Inline-code examples and HTML comments are not links on the rendered page,
  # so flagging them was a false failure on a document that renders fine.
  def test_skips_a_link_inside_an_inline_code_span
    assert_empty links("text `[not a link](nope.md)` more\n")
  end

  def test_skips_a_link_inside_an_html_comment
    assert_empty links("<!-- [commented](nope.md) -->\n")
  end

  # --- URL syntax the browser resolves before it reaches the filesystem ---

  def test_strips_a_query_string_from_the_target
    l = links('[q](quality-gates.md?plain=1)').first
    assert_equal 'docs/lifecycle/quality-gates.md', l.path
  end

  def test_decodes_percent_escapes_in_the_path
    l = links('[e](release%20notes.md)').first
    assert_equal 'docs/lifecycle/release notes.md', l.path
  end

  def test_decodes_percent_escapes_in_the_fragment
    l = links('[e](quality-gates.md#caf%C3%A9)').first
    assert_equal 'café', l.fragment
  end

  def test_empty_fragment_is_not_a_fragment
    assert_nil links('[top](quality-gates.md#)').first.fragment
  end

  # The renderer resolves character references while writing the href, so the
  # browser asks for `notes&draft.md`. Checked literally, a decoy file named
  # `notes&amp;draft.md` would have made the broken target pass.
  def test_decodes_character_references_in_the_target
    l = links('[x](notes&amp;draft.md)').first
    assert_equal 'docs/lifecycle/notes&draft.md', l.path
  end

  def test_decodes_character_references_in_the_fragment
    l = links('[x](quality-gates.md#fish-&amp;-chips)').first
    assert_equal 'fish-&-chips', l.fragment
  end

  def test_a_literal_ampersand_in_a_target_is_left_alone
    assert_equal %w[docs/lifecycle/notes&draft.md], paths('[x](notes&draft.md)')
  end
end

# --- The cmark-gfm oracle: the link set GitHub renders for the excluded files ---
#
# links_cmark reads links through commonmarker (comrak), the renderer GitHub uses
# for README/CONTRIBUTING/SECURITY/skills. It exists to catch the links kramdown
# and cmark-gfm disagree about — a reference label they case-fold differently, a
# target GitHub decodes a character reference in — which the site-only kramdown
# walk drops. bin/anchor-lint unions this set with the kramdown one.
class LinksCmarkTest < Minitest::Test
  def paths(text, source: 'docs/lifecycle/pr-lifecycle.md')
    AnchorContract::Extract.links_cmark(text, source: source).map(&:path)
  end

  def kramdown_paths(text, source: 'docs/lifecycle/pr-lifecycle.md')
    AnchorContract::Extract.links(text, source: source).map(&:path)
  end

  # Finding 1: kramdown lowercases a reference label, cmark-gfm applies full
  # Unicode case-folding (`ß` -> `ss`), so `[ss]` + `[ß]: missing.md` is a live
  # link on GitHub. kramdown resolves nothing and drops it; the cmark oracle
  # surfaces it so the missing target is checked.
  def test_surfaces_a_shortcut_reference_kramdown_case_folds_away
    assert_empty kramdown_paths("[ss]\n\n[ß]: bad.md\n")
    assert_equal %w[docs/lifecycle/bad.md], paths("[ss]\n\n[ß]: bad.md\n")
  end

  def test_surfaces_a_full_reference_kramdown_case_folds_away
    assert_equal %w[docs/lifecycle/bad.md], paths("[x][ß]\n\n[ß]: bad.md\n")
  end

  # Finding 6: cmark-gfm decodes the HTML5 character reference in the target, so
  # `a&sol;b.md` is the path `a/b.md` GitHub actually requests — resolved and
  # checked, not passed as the literal decoy string.
  def test_decodes_a_named_character_reference_in_the_target
    assert_equal %w[docs/lifecycle/a/b.md], paths("[x](a&sol;b.md)\n")
  end

  # A double-encoded target is the literal file `a&sol;b.md` on both renderers —
  # cmark-gfm decodes `&amp;` once and stops — so no false decode happens.
  def test_does_not_over_decode_a_double_encoded_target
    assert_equal %w[docs/lifecycle/a&sol;b.md], paths("[x](a&amp;sol;b.md)\n")
  end

  # The old regex grammar lost the wrapping link of an image-wrapped link; the
  # cmark oracle captures both, same as the kramdown one.
  def test_captures_both_targets_of_an_image_wrapped_link
    assert_equal %w[docs/lifecycle/badge.svg docs/lifecycle/gates.md],
                 paths("[![b](badge.svg)](gates.md)\n").sort
  end

  # Links inside code and comments are not rendered links on GitHub either.
  def test_skips_links_inside_code_and_comments
    assert_empty paths("`[x](nope.md)` and\n```\n[y](nope.md)\n```\n<!-- [z](nope.md) -->\n")
  end

  # External and same-file-fragment links are handled the same as the kramdown
  # oracle, so the union does not double-count or misroute them.
  def test_skips_external_targets
    assert_empty paths("[a](https://example.com) [b](mailto:x@y.z) [c](/abs.md)\n")
  end

  def test_reports_the_source_line_of_the_link
    l = AnchorContract::Extract.links_cmark("intro\n\nsee [g](gates.md)\n", source: 'index.md').first
    assert_equal 'gates.md', l.path
    assert_equal 3, l.line
  end

  # Front matter is stripped before the cmark parse, same as the kramdown path,
  # so a bracketed construct inside it is not read as a link.
  def test_ignores_front_matter
    assert_empty paths("---\nnav: \"[x](nope.md)\"\n---\n\n# Body\n")
  end

  # GitHub renders GFM footnotes, and a link inside a footnote definition is a
  # live link on the page. The site-only kramdown walk stores footnote bodies
  # out of reach; the cmark oracle surfaces the link so its target is checked.
  def test_surfaces_a_link_inside_a_footnote_definition
    assert_equal %w[docs/lifecycle/missing.md], paths("Body use[^p].\n\n[^p]: see [t](missing.md)\n")
  end

  # A raw <a>/<img> tag is markdown-inert to comrak's link nodes but a live link
  # on the GitHub page, so its target is pulled from the raw HTML too — otherwise
  # routing an excluded file to the cmark oracle would drop the kramdown path's
  # raw-link coverage.
  def test_extracts_a_raw_html_anchor_target
    assert_equal %w[docs/lifecycle/missing.md], paths(%(<a href="missing.md">x</a>\n))
  end

  def test_extracts_a_raw_html_image_target
    assert_equal %w[docs/lifecycle/pic.png], paths(%(<img src="pic.png">\n))
  end

  def test_extracts_a_raw_html_target_with_an_unquoted_value
    assert_equal %w[docs/lifecycle/unq.md], paths("<div>\n<a href=unq.md>y</a>\n</div>\n")
  end

  def test_skips_a_raw_html_link_inside_a_fence
    assert_empty paths("```\n<a href=\"nope.md\">x</a>\n```\n")
  end

  def test_skips_an_external_raw_html_link
    assert_empty paths(%(<a href="https://example.com">e</a>\n))
  end
end

# --- GitHub's heading-id set, for the files it renders directly ---
#
# heading_ids_cmark reads ids from cmark-gfm's own rendered anchors — the ids a
# reader on the GitHub file view actually lands on. It is used for the excluded
# files, where kramdown's slugger can diverge from GitHub's.
class HeadingIdsCmarkTest < Minitest::Test
  def ids(text) = AnchorContract::Extract.heading_ids_cmark(text)

  def test_matches_github_slugging_on_ordinary_headings
    assert_equal %w[the-pipeline fish--chips a-bold-heading],
                 ids("# The pipeline\n\n## Fish & Chips\n\n## A <em>bold</em> heading\n")
  end

  def test_counter_suffixes_duplicate_headings
    assert_equal %w[notes notes-1 notes-2], ids("# Notes\n# Notes\n# Notes\n")
  end

  def test_emits_setext_heading_ids
    assert_equal %w[underlined-heading], ids("Underlined heading\n==================\n")
  end

  # GitHub strips a literal tab from the slug (`foobar`) where kramdown keeps a
  # hyphen (`foo-bar`); the excluded files must be checked against this set.
  def test_slugs_a_tab_the_github_way
    assert_equal %w[foobar], ids("## foo\tbar\n")
    refute_includes AnchorContract::Extract.heading_ids("## foo\tbar\n"), 'foobar'
  end

  def test_ignores_front_matter
    assert_empty ids("---\ntitle: \"# Phantom\"\n---\n")
  end

  # cmark passes a raw <hN> through untouched. An explicit id is picked up; a raw
  # heading without one is not slugged here (reproducing GitHub's Unicode slugger
  # + duplicate counter is the drift the parser-backed design avoids, and no such
  # heading exists in the corpus).
  def test_keeps_an_explicit_raw_html_heading_id
    assert_equal %w[custom], ids(%(<h2 id="custom">X</h2>\n))
  end

  def test_keeps_an_explicit_raw_html_heading_id_once
    assert_equal %w[custom], ids(%(<h2 id="custom">X</h2>\n<h2 id="custom">Y</h2>\n))
  end

  def test_collects_markdown_and_explicit_raw_heading_ids_together
    assert_equal %w[md-one raw-two], ids(%(## MD One\n\n<h3 id="raw-two">Two</h3>\n))
  end
end

# --- Pure checker: each rule in isolation, with crafted sets ---
class CheckTest < Minitest::Test
  FILES = Set.new(%w[index.md docs/reference/glossary.md docs/reference/index.md
                     setup/config.template.yaml skills/README.md]).freeze
  DIRS = Set.new(%w[docs docs/reference setup skills]).freeze
  HEADINGS = { 'index.md' => %w[find-your-way],
               'docs/reference/glossary.md' => %w[fit-screen trust-ledger],
               'docs/reference/index.md' => %w[reference],
               'skills/README.md' => %w[skill-index] }.freeze

  def check(*links)
    AnchorContract.check(links: links, headings: HEADINGS, files: FILES, dirs: DIRS)
  end

  def link(path:, fragment: nil, href: 'x', source: 'index.md', line: 1)
    AnchorContract::Link.new(source: source, line: line, href: href, path: path, fragment: fragment)
  end

  def test_resolvable_link_is_clean
    assert_empty check(link(path: 'docs/reference/glossary.md'))
  end

  def test_missing_target_is_an_error
    v = check(link(path: 'docs/reference/ghost.md', href: 'docs/reference/ghost.md')).first
    assert_equal :missing, v.rule
  end

  def test_extensionless_link_to_a_real_doc_is_reported_as_extension
    v = check(link(path: 'docs/reference/glossary', href: 'docs/reference/glossary')).first
    assert_equal :extension, v.rule
    assert_match(/\.md/, v.message)
  end

  def test_directory_link_with_an_index_is_clean
    assert_empty check(link(path: 'docs/reference', href: 'docs/reference/'))
  end

  # GitHub renders a directory listing and the site resolves through index.md,
  # so an index is not required — only that the directory exists. skills/ is the
  # live case: excluded from the build, browsed on GitHub, no index.md.
  def test_directory_link_without_an_index_is_clean
    assert_empty check(link(path: 'setup', href: 'setup/'))
  end

  def test_link_to_a_nonexistent_directory_is_missing
    v = check(link(path: 'nope', href: 'nope/')).first
    assert_equal :missing, v.rule
  end

  def test_resolvable_fragment_is_clean
    assert_empty check(link(path: 'docs/reference/glossary.md', fragment: 'fit-screen'))
  end

  def test_unresolvable_fragment_is_an_error
    v = check(link(path: 'docs/reference/glossary.md', fragment: 'no-such-heading')).first
    assert_equal :fragment, v.rule
  end

  def test_same_file_fragment_is_checked_against_the_linking_file
    assert_empty check(link(path: '', fragment: 'find-your-way'))
    v = check(link(path: '', fragment: 'nope')).first
    assert_equal :fragment, v.rule
  end

  def test_fragment_on_a_non_markdown_target_is_ignored
    assert_empty check(link(path: 'setup/config.template.yaml', fragment: 'scope'))
  end

  # The site anchors a bare directory into index.md, GitHub into README.md. One
  # rule cannot serve both, so the link has to name the document — even when the
  # directory does hold an index and the id is real.
  def test_fragment_on_a_directory_is_an_error_even_with_an_index
    v = check(link(path: 'docs/reference', fragment: 'reference')).first
    assert_equal :fragment, v.rule
    assert_match(/name the document/, v.message)
  end

  def test_fragment_on_a_directory_is_an_error_even_with_a_readme
    v = check(link(path: 'skills', fragment: 'skill-index')).first
    assert_equal :fragment, v.rule
  end

  def test_fragment_on_a_directory_with_no_index_or_readme_is_an_error
    v = check(link(path: 'setup', fragment: 'scope')).first
    assert_equal :fragment, v.rule
  end

  def test_explicit_index_target_still_resolves_a_fragment
    assert_empty check(link(path: 'docs/reference/index.md', fragment: 'reference'))
  end

  def test_explicit_readme_target_still_resolves_a_fragment
    assert_empty check(link(path: 'skills/README.md', fragment: 'skill-index'))
  end

  def test_violation_line_names_source_and_target
    v = check(link(path: 'docs/ghost.md', href: 'docs/ghost.md', line: 42)).first
    assert_match(/index\.md:42/, v.to_line)
    assert_match(%r{docs/ghost\.md}, v.to_line)
  end
end

# --- The rendering assumptions the whole slugger rests on ---
#
# Checking only kramdown.input left three other settings able to re-slug every
# heading in the repo while the lint kept reading the ids it would have emitted.
class IdConfigTest < Minitest::Test
  def with_config(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, '_config.yml')
      File.write(path, yaml)
      yield path
    end
  end

  def conflicts(yaml)
    with_config(yaml) { |p| AnchorContract::Extract.id_config_conflicts(p) }
  end

  def test_absent_keys_inherit_jekylls_defaults
    assert_empty conflicts("markdown: kramdown\nkramdown:\n  syntax_highlighter: rouge\n")
  end

  def test_the_repos_own_settings_are_clean
    assert_empty AnchorContract::Extract.id_config_conflicts(
      File.expand_path('../_config.yml', __dir__)
    )
  end

  def test_explicit_gfm_passes
    assert_empty conflicts("kramdown:\n  input: GFM\n")
  end

  def test_native_kramdown_input_conflicts
    assert_match(/kramdown\.input/, conflicts("kramdown:\n  input: kramdown\n").first)
  end

  # Jekyll can convert with something other than kramdown entirely, and then no
  # kramdown key has to be wrong for every predicted id to be.
  def test_a_non_kramdown_converter_conflicts
    assert_match(/markdown/, conflicts("markdown: CommonMark\n").first)
  end

  # With auto_ids off the page has no anchors at all, so every fragment check
  # passes against ids only the lint believes in.
  def test_auto_ids_off_conflicts
    assert_match(/auto_ids/, conflicts("kramdown:\n  auto_ids: false\n").first)
  end

  def test_auto_id_prefix_conflicts
    assert_match(/auto_id_prefix/, conflicts("kramdown:\n  auto_id_prefix: p-\n").first)
  end

  def test_an_empty_auto_id_prefix_is_the_default
    assert_empty conflicts("kramdown:\n  auto_id_prefix: ''\n")
  end

  # A key written with no value merges as nil rather than as Jekyll's default.
  def test_a_valueless_key_conflicts
    assert_match(/auto_ids/, conflicts("kramdown:\n  auto_ids:\n").first)
  end

  def test_every_conflict_is_reported_not_just_the_first
    yaml = "markdown: CommonMark\nkramdown:\n  input: kramdown\n  auto_ids: false\n  auto_id_prefix: p-\n"
    assert_equal 4, conflicts(yaml).size
  end
end

# --- Constructs the site and GitHub render differently ---
#
# Kramdown is the site's renderer and only an approximation of GitHub's. Each
# case here is one the two disagree about, where scanning the document anyway
# would hide a link or bless an anchor that 404s on one of them.
class UnportableTest < Minitest::Test
  def rejections(text) = AnchorContract::Extract.unportable(text, source: 'README.md')

  def messages(text) = rejections(text).map(&:message)

  def test_a_clean_document_is_not_rejected
    md = "---\ntitle: x\n---\n\n# Heading\n\n[a](b.md) and <a href=\"c.md\">c</a>\n"
    assert_empty rejections(md)
  end

  # kramdown honours the attribute; GitHub prints it and slugs the heading text,
  # so a link to #my-id resolves here and 404s there.
  def test_a_block_ial_heading_id_is_rejected
    assert_match(/explicit heading id #my-id/, messages("## Auto slug\n{: #my-id}\n").first)
  end

  def test_a_brace_heading_id_is_rejected
    assert_match(/explicit heading id #my-id/, messages("## Auto slug {#my-id}\n").first)
  end

  def test_a_generated_id_is_not_rejected
    assert_empty rejections("## Auto slug\n")
  end

  # Only the id attribute is unportable — a class IAL renders the same heading
  # on both, and just-the-docs pages use them.
  def test_a_class_only_ial_is_not_rejected
    assert_empty rejections("## Auto slug\n{: .no_toc }\n")
  end

  # kramdown drops the whole tag to literal text; GitHub renders it as a link,
  # so its target would never be checked.
  def test_an_unquoted_html_attribute_is_rejected
    assert_match(/raw <a>/, messages("<a href=missing.md>x</a>\n").first)
  end

  def test_an_unquoted_html_attribute_inside_a_block_is_rejected
    assert_match(/raw <a>/, messages("<div>\n<a href=missing.md>x</a>\n</div>\n").first)
  end

  def test_a_quoted_html_link_is_not_rejected
    assert_empty rejections(%(<div align="center">\n<a href="q.md">x</a>\n</div>\n))
  end

  # `<` in prose is not a tag, and a tag inside code is an example.
  def test_comparison_operators_in_prose_are_not_rejected
    assert_empty rejections("a < b and c > d, the <animal> tag\n")
  end

  def test_a_link_tag_inside_a_code_span_is_not_rejected
    assert_empty rejections("write it as `<a href=x.md>` here\n")
  end

  def test_a_link_tag_inside_a_fence_is_not_rejected
    assert_empty rejections("```html\n<a href=x.md>x</a>\n```\n")
  end

  # Jekyll's front-matter regex does not match past a BOM, so the front matter
  # is rendered as body text and its `#` lines become real headings — on the
  # site only. Rejected rather than modelled per renderer.
  def test_a_byte_order_mark_is_rejected
    assert_match(/byte-order mark/, messages("\uFEFF---\ntitle: x\n---\n\n# Real\n").first)
  end







  def test_the_rejection_names_the_file_and_line
    r = AnchorContract::Extract.unportable("# Fine\n\n## Auto slug {#my-id}\n", source: 'docs/x.md').first
    assert_equal 'docs/x.md', r.source
    assert_equal 3, r.line
    assert_match(%r{docs/x\.md:3}, r.to_line)
  end

  # A heading the site and GitHub slug differently is an anchor that resolves on
  # one and 404s on the other. A literal tab gives `foo-bar` under kramdown and
  # `foobar` under cmark-gfm, so a doc both renderers publish is rejected rather
  # than checked against an id set that is wrong on one of the two pages.
  def test_a_heading_the_renderers_slug_differently_is_rejected
    assert_match(/slug it differently|slug them differently|slug differently/,
                 messages("## foo\tbar\n").first)
  end

  def test_a_heading_both_renderers_slug_alike_is_not_rejected
    assert_empty rejections("## Normal Heading\n\n## Another One\n")
  end
end

# --- Discovery: git-tracked enumeration reaches dot-dirs, skips untracked ---
class DiscoveryTest < Minitest::Test
  def with_repo
    Dir.mktmpdir do |dir|
      system('git', 'init', '-q', dir, exception: true)
      system('git', '-C', dir, 'config', 'user.email', 't@t.t', exception: true)
      system('git', '-C', dir, 'config', 'user.name', 't', exception: true)
      # Neutralize any global excludesFile so a developer's personal ignores
      # (e.g. docs/) can't make the fixtures untracked and the assertions flaky.
      system('git', '-C', dir, 'config', 'core.excludesFile', '/dev/null', exception: true)
      yield dir
    end
  end

  def write(dir, rel, body = "# x\n")
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def add_all(dir)
    system('git', '-C', dir, 'add', '-A', exception: true)
  end

  def test_tracked_dot_directory_markdown_is_discovered
    with_repo do |dir|
      write(dir, '.github/PULL_REQUEST_TEMPLATE/bug.md')
      write(dir, 'docs/index.md')
      add_all(dir)
      assert_equal ['.github/PULL_REQUEST_TEMPLATE/bug.md', 'docs/index.md'],
                   AnchorContract::Extract.markdown_files(dir)
    end
  end

  def test_untracked_markdown_is_ignored
    with_repo do |dir|
      write(dir, 'tracked.md')
      system('git', '-C', dir, 'add', 'tracked.md', exception: true)
      write(dir, 'scratch.md') # never staged
      assert_equal ['tracked.md'], AnchorContract::Extract.markdown_files(dir)
    end
  end

  def test_repo_entries_derives_directories_from_tracked_files
    with_repo do |dir|
      write(dir, 'docs/reference/glossary.md')
      add_all(dir)
      files, dirs = AnchorContract::Extract.repo_entries(dir)
      assert_includes files, 'docs/reference/glossary.md'
      assert_includes dirs, 'docs'
      assert_includes dirs, 'docs/reference'
    end
  end

  # Both renderers publish these, but markdown_files only enumerates *.md, so
  # their links would go unchecked. The lint rejects the filename instead.
  def test_markdown_outside_the_md_convention_is_reported_as_stray
    with_repo do |dir|
      write(dir, 'BROKEN.MD')
      write(dir, 'notes.markdown')
      write(dir, 'fine.md')
      add_all(dir)
      assert_equal ['fine.md'], AnchorContract::Extract.markdown_files(dir)
      assert_equal ['BROKEN.MD', 'notes.markdown'],
                   AnchorContract::Extract.stray_markdown_files(dir)
    end
  end

  # The set is the union of the two renderers' own lists: Jekyll's markdown_ext
  # default and github-markup's /md|mkdn?|mdwn|mdown|markdown|mdx|litcoffee/i.
  # GitHub routes .mdx and .litcoffee through markdown, so a broken link in one
  # is live; neither renderer treats .text or .mdtext as markdown, so rejecting
  # those was a failure on a file that is not in the contract at all.
  def test_the_stray_set_is_the_union_of_both_renderers
    with_repo do |dir|
      %w[a.mdx b.litcoffee c.mkdown d.mdwn e.text f.mdtext].each { |f| write(dir, f) }
      add_all(dir)
      assert_equal %w[a.mdx b.litcoffee c.mkdown d.mdwn],
                   AnchorContract::Extract.stray_markdown_files(dir).sort
    end
  end

  def test_a_clean_repo_has_no_strays
    with_repo do |dir|
      write(dir, 'fine.md')
      write(dir, 'setup/config.yaml', "a: 1\n")
      add_all(dir)
      assert_empty AnchorContract::Extract.stray_markdown_files(dir)
    end
  end

  # _config.yml's exclude list is what Jekyll keeps out of the built site, and
  # exactly the files GitHub is the sole renderer for. site_excluded_markdown
  # honours both a literal path entry and a directory-prefix entry.
  def test_site_excluded_markdown_reads_the_config_exclude_list
    with_repo do |dir|
      write(dir, 'README.md')
      write(dir, 'docs/index.md')
      write(dir, 'skills/one/SKILL.md')
      write(dir, 'index.md')
      File.write(File.join(dir, '_config.yml'), "exclude:\n  - README.md\n  - skills/\n")
      add_all(dir)
      excluded = AnchorContract::Extract.site_excluded_markdown(dir, File.join(dir, '_config.yml'))
      assert_equal %w[README.md skills/one/SKILL.md], excluded.to_a.sort
      refute_includes excluded, 'docs/index.md'
      refute_includes excluded, 'index.md'
    end
  end

  def test_site_excluded_markdown_is_empty_with_no_exclude_key
    with_repo do |dir|
      write(dir, 'README.md')
      File.write(File.join(dir, '_config.yml'), "title: x\n")
      add_all(dir)
      assert_empty AnchorContract::Extract.site_excluded_markdown(dir, File.join(dir, '_config.yml'))
    end
  end

  # Jekyll matches an exclude entry as a glob too, and `*` does not cross a `/`.
  def test_site_excluded_markdown_honours_a_glob_entry
    with_repo do |dir|
      write(dir, 'docs/top.md')
      write(dir, 'docs/sub/deep.md')
      File.write(File.join(dir, '_config.yml'), "exclude:\n  - 'docs/*.md'\n")
      add_all(dir)
      excluded = AnchorContract::Extract.site_excluded_markdown(dir, File.join(dir, '_config.yml'))
      assert_includes excluded, 'docs/top.md'
      refute_includes excluded, 'docs/sub/deep.md'
    end
  end

  # An include entry wins over a matching exclude, exactly as Jekyll resolves it.
  def test_site_excluded_markdown_respects_an_include_override
    with_repo do |dir|
      write(dir, 'README.md')
      write(dir, 'docs/keep.md')
      File.write(File.join(dir, '_config.yml'),
                 "exclude:\n  - README.md\n  - 'docs/*.md'\ninclude:\n  - docs/keep.md\n")
      add_all(dir)
      excluded = AnchorContract::Extract.site_excluded_markdown(dir, File.join(dir, '_config.yml'))
      assert_includes excluded, 'README.md'
      refute_includes excluded, 'docs/keep.md'
    end
  end

  # End-to-end routing: an excluded file (GitHub-rendered) whose link target
  # carries an HTML5 character reference resolving to a real file must pass —
  # the earlier unconditional kramdown union false-flagged it because kramdown
  # left the entity undecoded. Routed through the cmark oracle, `dir&sol;t.md`
  # is the path `dir/t.md`, which exists.
  def test_an_excluded_file_entity_target_that_resolves_is_not_flagged
    with_repo do |dir|
      write(dir, 'dir/t.md')
      write(dir, 'README.md', "# R\n\n[x](dir&sol;t.md)\n")
      File.write(File.join(dir, '_config.yml'), "exclude:\n  - README.md\n")
      add_all(dir)
      excluded = AnchorContract::Extract.site_excluded_markdown(dir, File.join(dir, '_config.yml'))
      assert_includes excluded, 'README.md'

      text = File.read(File.join(dir, 'README.md'))
      links = AnchorContract::Extract.links_cmark(text, source: 'README.md')
      files, dirs = AnchorContract::Extract.repo_entries(dir)
      violations = AnchorContract.check(links: links, headings: {}, files: files, dirs: dirs)
      assert_empty violations
      assert_equal %w[dir/t.md], links.map(&:path)
    end
  end
end
