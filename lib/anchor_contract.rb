# frozen_string_literal: true

require 'set'
require 'cgi'
require 'yaml'
require 'pathname'
require 'kramdown'
require 'kramdown-parser-gfm'
require 'commonmarker'

# Enforces the cross-document link contract: every relative markdown link
# resolves to a real file, and every #fragment resolves to a real heading.
#
# This covers what html-proofer cannot. _config.yml excludes README.md,
# CONTRIBUTING.md, docs/README.md, SECURITY.md, skills/ and setup/*.yaml from
# the build, so links inside them are checked by nothing else — and those files
# are read on GitHub, where a link that the site resolves may still 404.
#
# Split into a pure checker (AnchorContract.check — resolved sets in, violations
# out) and an Extract module that reads the repo, mirroring lib/skills_contract.rb.
#
# Extraction runs the real parsers. Heading ids come from kramdown-parser-gfm —
# the same parser Jekyll renders this site with, and the one whose slugger
# mirrors github-slugger for the files GitHub renders directly. Links are read
# from BOTH renderers and unioned: kramdown for the site, and cmark-gfm (via
# commonmarker) for the excluded files GitHub renders directly. An earlier
# revision reimplemented both the link grammar and the slugger with regexes; a
# hand-written grammar cannot keep up with nested brackets, escaped delimiters,
# image-wrapped links, block IALs or reference headings, and every gap there is
# a broken link the gate silently blesses. Asking the renderers is the only way
# the prediction cannot drift from the page.
#
# Two renderers, read directly. Kramdown is exactly right for the site, and
# close but not identical to the cmark-gfm GitHub renders the excluded files
# with — the two disagree about reference-label case-folding (kramdown
# lowercases, cmark-gfm applies full Unicode folding) and about character
# references in link targets. Rather than model that difference, both link sets
# are collected and checked: a link either renderer produces is a link on the
# page it renders. Where the disagreement instead hides an *anchor* —
# kramdown-only heading attributes, raw HTML kramdown declines to parse — the
# construct is rejected (Extract.unportable) rather than scanned, because an id
# only one renderer emits is an anchor that 404s on the other.
module AnchorContract
  Link = Struct.new(:source, :line, :href, :path, :fragment, keyword_init: true)

  Violation = Struct.new(:rule, :link, :message, keyword_init: true) do
    def to_line
      "  x #{link.source}:#{link.line} -> #{link.href} — #{message}"
    end
  end

  # A construct that is not itself a broken link, but takes one out of reach of
  # the gate. Reported with its own message rather than folded into Violation,
  # which always names a link.
  Rejection = Struct.new(:source, :line, :message, keyword_init: true) do
    def to_line
      "  x #{source}:#{line} — #{message}"
    end
  end

  # Pure. Given the resolved sets, return the list of violations.
  #
  # links    — every relative markdown link found in the repo
  # headings — repo-relative markdown path => heading ids it offers
  # files    — every repo-relative file path
  # dirs     — every repo-relative directory path
  def self.check(links:, headings:, files:, dirs:)
    links.filter_map { |link| check_link(link, headings, files, dirs) }
  end

  def self.check_link(link, headings, files, dirs)
    doc = resolve(link, files, dirs)
    return doc if doc.is_a?(Violation)
    return nil if doc.nil? || link.fragment.nil?
    return nil unless doc.end_with?('.md')

    ids = headings.fetch(doc, [])
    return nil if ids.include?(link.fragment)

    Violation.new(rule: :fragment, link: link,
                  message: "no heading in #{doc} produces the anchor ##{link.fragment}")
  end
  private_class_method :check_link

  # The markdown document a link points at, or nil when the target is a real
  # non-markdown file (or a bare directory with nothing to anchor into), or a
  # Violation when the target does not resolve.
  def self.resolve(link, files, dirs)
    return link.source if link.path.empty?

    # A directory link is valid as long as the directory exists: GitHub renders
    # its file listing. A #fragment on one is not, because the two renderers
    # disagree about which document supplies the headings — the site serves
    # index.md, GitHub serves README.md, and a directory rarely holds both. The
    # target has to name the document, the same way an extensionless link does.
    if dirs.include?(link.path)
      return nil if link.fragment.nil?

      return Violation.new(rule: :fragment, link: link,
                           message: "##{link.fragment} on directory #{link.path} — the site anchors " \
                                    'into index.md and GitHub into README.md; name the document')
    end

    if files.include?(link.path)
      return link.path if link.path.end_with?('.md')

      return nil
    end

    if files.include?("#{link.path}.md")
      return Violation.new(rule: :extension, link: link,
                           message: "extensionless link — resolves on the site but 404s on GitHub; write #{link.path}.md")
    end

    Violation.new(rule: :missing, link: link, message: 'target does not exist')
  end
  private_class_method :resolve

  # Repo readers. Each is small and testable against fixture strings.
  module Extract
    EXTERNAL = %r{\A(?:[a-z][a-z0-9+.-]*:|//|/)}i.freeze
    # Jekyll's own front-matter delimiters: a leading `---` line through the next
    # `---` or `...` line. Jekyll's regex ends `$\n?`, so the closing delimiter
    # may sit at EOF with no trailing newline — a file ending `# phantom\n---`
    # has that heading stripped, and requiring the newline exposed it as an
    # anchor the page never emits.
    FRONT_MATTER = /\A---[ \t]*\r?\n.*?^(?:---|\.\.\.)[ \t]*(?:\r?\n|\z)/m.freeze
    # The union of what the two renderers route through markdown: Jekyll's
    # markdown_ext default (markdown,mkdown,mkdn,mkd,md) and github-markup's
    # /md|mkdn?|mdwn|mdown|markdown|mdx|litcoffee/i. Everything tracked here is
    # expected to be `.md`; the rest are rejected rather than skipped.
    MARKDOWN_EXT = /\.(?:md|markdown|mkd|mkdn|mkdown|mdown|mdwn|mdx|litcoffee)\z/i.freeze
    # Raw HTML in a page still produces a link the reader can follow.
    HTML_LINK_ATTR = { 'a' => 'href', 'img' => 'src' }.freeze
    PERCENT_ESCAPE = /%([0-9A-Fa-f]{2})/.freeze
    BOM = "\uFEFF"
    # A link tag sitting in a text node is one the markdown parser declined to
    # read — an unquoted attribute value is the usual cause. GitHub's parser
    # accepts them, so the target would go unchecked.
    RAW_HTML_LINK = /<(?:a|img)\b[^>]*>/i.freeze
    # The same tags, captured whole for target extraction from raw-HTML nodes.
    RAW_HTML_TAG = /<(?:a|img)\b[^>]*>/i.freeze
    RAW_HTML_MESSAGE = 'raw <a>/<img> tag the markdown parser could not read — an unquoted ' \
                       'attribute value renders as literal text on the site and as a live link ' \
                       'on GitHub, leaving its target unchecked'
    BOM_MESSAGE = 'byte-order mark before the front matter — Jekyll then leaves the front matter ' \
                  'unstripped and renders it as body text; delete the BOM'

    # cmark-gfm options mirroring GitHub's own render pipeline (GFM extensions on,
    # footnotes on, smart punctuation off) so the second oracle sees links and
    # heading ids exactly as GitHub does. Frozen so every caller shares one config.
    COMMONMARK_OPTIONS = {
      extension: { table: true, autolink: true, tagfilter: true, strikethrough: true,
                   tasklist: true, footnotes: true, header_ids: '' },
      parse: { smart: false },
      render: { unsafe: true }
    }.freeze

    module_function

    # The parsed page, exactly as Jekyll builds it. The parser and its id-bearing
    # options are asserted separately by id_config_conflicts — the slugger only
    # mirrors github-slugger under GFM with Jekyll's own defaults.
    def document(text, **opts)
      Kramdown::Document.new(strip_front_matter(text), input: 'GFM', **opts)
    end

    # Jekyll strips leading YAML front matter before kramdown sees the page, and
    # GitHub renders it as a table rather than markdown, so a `# comment` inside
    # it is not a heading on either. Blanked rather than deleted so the line
    # numbers kramdown reports still match the file.
    def strip_front_matter(text)
      text.sub(FRONT_MATTER) { |matter| "\n" * matter.count("\n") }
    end

    # Heading ids a markdown document offers, in document order — whatever the
    # renderer emits, including the duplicate counter and Setext underlines.
    # Explicit `{#id}` and `{: #id}` attributes land here too, but they are a
    # kramdown extension GitHub prints as literal text, so unportable rejects the
    # document before any of these ids are trusted. This is the *site* renderer's
    # id set; heading_ids_cmark gives GitHub's, and each file is checked against
    # the renderer that publishes it (see anchor-lint).
    def heading_ids(text)
      ids = []
      walk(document(text).root) { |el| ids << el.attr['id'] if el.type == :header }
      ids.compact
    end

    # Heading ids GitHub emits, read from cmark-gfm's own rendered anchors. Used
    # for the files excluded from the Jekyll site, which GitHub renders directly
    # and whose ids can differ from kramdown's — a heading with a literal tab
    # slugs to `foo-bar` in kramdown but `foobar` here, and an anchor link is
    # only valid against the renderer that actually served the page. header_ids
    # is enabled in COMMONMARK_OPTIONS, so every markdown heading carries the id
    # attribute; a raw <hN id="..."> is passed through verbatim by cmark, so its
    # explicit id is picked up too.
    def heading_ids_cmark(text)
      body = strip_front_matter(text)
      html = Commonmarker.to_html(body, options: COMMONMARK_OPTIONS)
      (html.scan(%r{<h[1-6][^>]*\sid="([^"]*)"}).flatten + raw_heading_ids(body)).uniq
    end

    # Explicit ids on raw <hN id="..."> tags, which cmark leaves untouched. A raw
    # heading *without* an id is deliberately not slugged here: GitHub's sanitizer
    # would assign one, but reproducing its full Unicode slugger and duplicate
    # counter is the drift the parser-backed design exists to avoid, and a bare
    # raw <hN> in markdown is an anti-pattern with no instance in the corpus.
    def raw_heading_ids(text)
      text.scan(%r{<h[1-6]\b[^>]*\bid\s*=\s*["']?([^"'\s>]+)}i).flatten
    end

    # Constructs the two renderers disagree about. Each one hides a link or an
    # anchor from the gate, so the document is rejected rather than scanned.
    #
    # Explicit heading ids are found by re-parsing with auto_ids off: whatever id
    # survives that was written into the source rather than generated, which is
    # exactly the set GitHub renders as literal text. Asking the parser this way
    # keeps the slugger unimplemented here.
    def unportable(text, source:)
      out = []
      out << Rejection.new(source: source, line: 1, message: BOM_MESSAGE) if text.start_with?(BOM)
      line = 1
      walk(document(text, auto_ids: false).root) do |el|
        line = el.options[:location] || line
        message = unportable_message(el)
        out << Rejection.new(source: source, line: line, message: message) if message
      end
      out.concat(divergent_heading_ids(text, source: source))
      out
    end

    # A heading the site and GitHub slug differently is an anchor that resolves
    # on one renderer and 404s on the other — a literal tab gives `foo-bar` under
    # kramdown and `foobar` under cmark-gfm. For a doc both publish, neither id is
    # trustworthy, so the document is rejected rather than checked against a set
    # that is wrong on one page. Reported for the included docs only; the excluded
    # ones are read through the cmark ids alone and have no second renderer to
    # disagree with.
    def divergent_heading_ids(text, source:)
      site = heading_ids(text)
      github = heading_ids_cmark(text)
      return [] if site == github

      [Rejection.new(source: source, line: 1,
                     message: 'heading id the site and GitHub slug differently ' \
                              "(kramdown #{(site - github).inspect}, cmark-gfm #{(github - site).inspect}) " \
                              '— an anchor to it resolves on one renderer and 404s on the other; ' \
                              'rephrase the heading so both slug it the same way')]
    end

    # Both renderers' link sets for one document, deduped by resolved identity so
    # a link they agree on is counted once while one only cmark sees (a reference
    # label they case-fold differently, a raw-HTML target, a decoded character
    # reference) or resolves elsewhere is kept and checked.
    def merged_links(text, source:)
      dedup_links(links(text, source: source) + links_cmark(text, source: source))
    end

    # Collapse links that resolve to the same target/fragment, keeping the first.
    # A raw <a> and a markdown link to the same file, or an href written two ways
    # that resolve alike, are one broken (or fine) target, not two diagnostics.
    def dedup_links(links)
      seen = {}
      links.each { |link| seen[[link.source, link.path, link.fragment]] ||= link }
      seen.values
    end

    def unportable_message(element)
      if element.type == :header && element.attr['id']
        id = element.attr['id']
        "explicit heading id ##{id} — kramdown honours it, GitHub prints the attribute as literal " \
          "text, so ##{id} 404s there; drop it and link the generated slug"
      elsif element.type == :text && element.value.match?(RAW_HTML_LINK)
        RAW_HTML_MESSAGE
      end
    end

    # Relative markdown links, with the target resolved to a repo-relative path.
    # Read from BOTH renderers and unioned by the caller: kramdown is exact for
    # the site, and cmark-gfm (links_cmark) is exact for the files GitHub renders
    # directly. A link only one of them sees — a reference label they case-fold
    # differently, a target GitHub decodes a character reference in — is still a
    # link on the page it renders, so the gate has to check it.
    def links(text, source:)
      dir = File.dirname(source)
      out = []
      walk(document(text).root) do |el|
        href = link_target(el)
        next if href.nil? || href.empty? || href.match?(EXTERNAL)

        out << build_link(href, source, dir, el.options[:location] || 1)
      end
      out
    end

    # The cmark-gfm oracle. commonmarker (comrak) resolves reference links,
    # character references, and nested/image-wrapped links exactly as GitHub's
    # renderer does, so its link set is what a reader on the GitHub file view can
    # actually click. Its urls arrive already entity-decoded (`a&sol;b.md` ->
    # `a/b.md`), so build_link's own CGI.unescapeHTML is a no-op second pass.
    # Raw <a>/<img> tags are markdown-inert to comrak's link nodes but live links
    # on the GitHub page, so their targets are pulled from the raw HTML too.
    def links_cmark(text, source:)
      dir = File.dirname(source)
      out = []
      walk_cmark(cmark_document(text)) do |node|
        if %i[link image].include?(node.type)
          href = node.url.to_s
        elsif %i[html_inline html_block].include?(node.type)
          out.concat(raw_html_links(node, source, dir))
          next
        else
          next
        end
        next if href.empty? || href.match?(EXTERNAL)

        line = (node.source_position || {})[:start_line] || 1
        out << build_link(href, source, dir, line)
      end
      out
    end

    # Every <a href>/<img src> in a raw-HTML node's own source. comrak keeps raw
    # HTML verbatim rather than as link nodes, but GitHub renders it as live
    # links, so the same targets kramdown reads through :html_element are checked
    # here for the files routed to the cmark oracle alone.
    def raw_html_links(node, source, dir)
      html = node.to_commonmark
      line = (node.source_position || {})[:start_line] || 1
      html.scan(RAW_HTML_TAG).filter_map do |tag_source|
        href = raw_html_target(tag_source)
        next if href.nil? || href.empty? || href.match?(EXTERNAL)

        build_link(href, source, dir, line)
      end
    end

    # The href/src of a single raw tag, or nil when it carries neither. Quoted
    # and unquoted attribute values are both read — GitHub follows either.
    def raw_html_target(tag_source)
      name = tag_source[/<\s*([a-z]+)/i, 1]&.downcase
      attr = HTML_LINK_ATTR[name]
      return nil unless attr

      tag_source[/#{attr}\s*=\s*"([^"]*)"/i, 1] ||
        tag_source[/#{attr}\s*=\s*'([^']*)'/i, 1] ||
        tag_source[/#{attr}\s*=\s*([^\s>]+)/i, 1]
    end

    def cmark_document(text)
      Commonmarker.parse(strip_front_matter(text), options: COMMONMARK_OPTIONS)
    end

    def walk_cmark(node, &block)
      yield node
      node.each { |child| walk_cmark(child, &block) }
    end

    def walk(element, &block)
      yield element
      element.children.each { |child| walk(child, &block) }
    end

    def link_target(element)
      case element.type
      when :a then element.attr['href']
      when :img then element.attr['src']
      when :html_element then element.attr[HTML_LINK_ATTR[element.value]]
      end
    end

    def build_link(href, source, dir, line)
      # Character references are resolved by the renderer, not the browser, so
      # they are undone before the URL is read: `foo&amp;bar.md` is the file
      # `foo&bar.md`. Percent escapes are the browser's and are decoded per
      # component below, after `#` has done its splitting.
      target, fragment = CGI.unescapeHTML(href).split('#', 2)
      # A query string is stripped by every renderer before the path is resolved,
      # and percent escapes are decoded, so `foo%20bar.md?v=1` is the tracked
      # file `foo bar.md`.
      rel = decode(target.to_s.split('?', 2).first.to_s)
      path = rel.empty? ? '' : Pathname.new(File.join(dir, rel)).cleanpath.to_s
      Link.new(source: source, line: line, href: href, path: path,
               fragment: fragment.nil? || fragment.empty? ? nil : decode(fragment))
    end

    def decode(str)
      str.gsub(PERCENT_ESCAPE) { Regexp.last_match(1).hex.chr }.force_encoding(Encoding::UTF_8)
    end

    # Every tracked markdown file, repo-relative. Git-tracked enumeration keeps
    # the gate harness-neutral: it naturally covers .github/**/*.md, excludes
    # untracked scratch (_site/, .worktrees/, agent logs), and needs no runtime-
    # specific skip list.
    def markdown_files(root)
      tracked_files(root).select { |rel| rel.end_with?('.md') }.sort
    end

    # Tracked files that render as markdown but sit outside the `.md` convention
    # markdown_files enumerates. Silently skipping one would leave its links
    # unchecked, so the lint rejects the filename instead.
    def stray_markdown_files(root)
      tracked_files(root).select { |rel| rel.match?(MARKDOWN_EXT) && !rel.end_with?('.md') }.sort
    end

    # [files, dirs] as repo-relative Sets, for link resolution. Directories are
    # derived from the tracked file paths — a directory "exists" for a link iff it
    # holds tracked content, which is exactly what GitHub renders a listing for.
    def repo_entries(root)
      files = Set.new
      dirs = Set.new
      tracked_files(root).each do |rel|
        files << rel
        Pathname.new(rel).dirname.descend { |d| dirs << d.to_s unless d.to_s == '.' }
      end
      [files, dirs]
    end

    def tracked_files(root)
      out = IO.popen(['git', '-C', root, 'ls-files', '-z'], &:read)
      raise "git ls-files failed in #{root}" unless $?&.success?

      out.split("\x00").reject(&:empty?)
    end

    # The set of tracked markdown files _config.yml excludes from the built site.
    # These are rendered by nobody but GitHub, so they are checked against the
    # cmark-gfm oracle rather than kramdown — a link or heading id read with the
    # site's parser would be judged by a renderer that never publishes the file.
    #
    # Jekyll's own matcher (Jekyll::EntryFilter) treats each exclude entry as a
    # literal path, a directory prefix, or a glob, and an `include` entry wins
    # over a matching exclude. Both rules are reproduced here so the routing lands
    # a file on the same side Jekyll would, whatever shape the config takes.
    def site_excluded_markdown(root, config_path)
      cfg = YAML.safe_load(File.read(config_path)) || {}
      excludes = Array(cfg['exclude'])
      includes = Array(cfg['include'])
      Set.new(markdown_files(root).select do |rel|
        excluded?(rel, excludes) && !excluded?(rel, includes)
      end)
    rescue Psych::Exception => e
      raise "could not parse #{config_path}: #{e.message}"
    end

    # True when the path matches a config entry the way Jekyll matches it: a
    # literal path, a directory prefix (`skills/` or `skills`), or a glob
    # (`docs/*.md`). FNM_PATHNAME keeps `*` from crossing `/`, matching Jekyll.
    def excluded?(rel, entries)
      entries.any? do |entry|
        pattern = entry.to_s.chomp('/')
        next false if pattern.empty?

        rel == pattern ||
          rel.start_with?("#{pattern}/") ||
          File.fnmatch?(pattern, rel, File::FNM_PATHNAME | File::FNM_DOTMATCH) ||
          File.fnmatch?("#{pattern}/**", rel, File::FNM_PATHNAME | File::FNM_DOTMATCH)
      end
    end

    # Every _config.yml setting that would make the site's heading ids differ
    # from the ones extraction reads, named so the failure can say which. Empty
    # means the lint's ids are the page's ids.
    #
    # Heading ids only mirror github-slugger while Jekyll converts with kramdown
    # running its GFM parser and generating ids the way it does by default. Each
    # key below is absent from Jekyll's defaults or set to the value extraction
    # assumes, so an absent key passes; any other value silently re-slugs every
    # heading in the repo and invalidates all 125 anchor checks at once.
    def id_config_conflicts(config_path)
      cfg = YAML.safe_load(File.read(config_path)) || {}
      kramdown = cfg['kramdown'] || {}
      [conflict(cfg, 'markdown', 'kramdown'),
       conflict(kramdown, 'input', 'GFM', prefix: 'kramdown.'),
       conflict(kramdown, 'auto_ids', true, prefix: 'kramdown.'),
       conflict(kramdown, 'auto_id_prefix', '', prefix: 'kramdown.')].compact
    rescue Psych::Exception => e
      raise "could not parse #{config_path}: #{e.message}"
    end

    # nil when the key is absent (Jekyll's default applies) or already carries
    # the assumed value; otherwise the setting, written the way the file does.
    # Present-but-empty is a conflict, not a default: the merged value is nil,
    # not what Jekyll would have supplied.
    def conflict(cfg, key, assumed, prefix: '')
      return nil unless cfg.key?(key)

      value = cfg[key]
      return nil if value == assumed
      return nil if assumed.is_a?(String) && value.to_s.casecmp?(assumed)

      "#{prefix}#{key}: #{value.inspect} (this lint reads ids as if it were #{assumed.inspect})"
    end
  end
end
