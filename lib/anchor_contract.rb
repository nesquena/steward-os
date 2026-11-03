# frozen_string_literal: true

require 'set'
require 'yaml'
require 'pathname'
require 'kramdown'
require 'kramdown-parser-gfm'
require 'commonmarker'
require 'nokogiri'
require 'jekyll'

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
      AnchorContract.printable("  x #{link.source}:#{link.line} -> #{link.href} — #{message}")
    end
  end

  # A report line can carry a NUL or another control character (a decoded href or fragment, a tracked file
  # name, a parser's message). It is printed escaped (`\u0000`, `\e`), the way String#inspect writes it, so the
  # report stays one readable line. A format character (a bidi override, a zero-width space), which inspect
  # leaves as it is, is written `\u202E`, so it cannot reorder or hide the text around it.
  def self.printable(str)
    str.gsub(/[^[:print:]]|\p{Cf}/) do |char|
      next char.inspect[1..-2] unless char.match?(/\p{Cf}/)

      char.ord > 0xFFFF ? format('\\u{%X}', char.ord) : format('\\u%04X', char.ord)
    end
  end

  # A construct that is not itself a broken link, but takes one out of reach of
  # the gate. Reported with its own message rather than folded into Violation,
  # which always names a link.
  Rejection = Struct.new(:source, :line, :message, keyword_init: true) do
    def to_line
      AnchorContract.printable("  x #{source}:#{line} — #{message}")
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
    # A path no file can have (build_link left it nil) is missing. It is rejected rather than
    # sanitized: a replacement character could alias a real tracked file.
    return Violation.new(rule: :missing, link: link, message: 'target does not exist') if link.path.nil?
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
    LINK_TAGS = 'a[href], img[src]'
    HEADING_TAGS = 'h1, h2, h3, h4, h5, h6'
    # The cmark node types that hold raw HTML verbatim.
    RAW_HTML_NODES = %i[html_inline html_block].freeze
    # The three fields of a Jekyll::Site that Jekyll::EntryFilter reads.
    JekyllSite = Struct.new(:source, :exclude, :include)
    # A link tag sitting whole in a text node is one kramdown declined to read.
    RAW_HTML_TAG = /<(?:a|img)\b[^>]*>/i.freeze
    # Wrappers whose content an HTML parser reads as text or drops, but which do
    # not survive on GitHub: the first nine are the GFM tagfilter's own list,
    # escaped to text by cmark-gfm, and the sanitizer strips <select>. Whatever
    # sits inside them is live markup on the page.
    NEUTRALIZED_TAG = %r{<(?=/?(?:title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext|select)\b)}i.freeze
    RAW_HTML_MESSAGE = 'raw <a>/<img> tag the site and GitHub read differently — usually an unquoted ' \
                       'attribute value, which renders as literal text on the site and as a live ' \
                       'link on GitHub, leaving its target unchecked'
    BOM_MESSAGE = 'byte-order mark before the front matter — Jekyll then doesn\'t see the front matter and ' \
                  'copies the page unrendered; delete the BOM'
    # Jekyll's own test for a page it renders (Utils.has_yaml_header?): an opening `---` line, closed or not.
    JEKYLL_YAML_HEADER = /\A---\s*\r?\n/.freeze

    # cmark-gfm options mirroring GitHub's own render pipeline (GFM extensions on,
    # footnotes on, smart punctuation off) so the second oracle sees links and
    # heading ids exactly as GitHub does. Frozen so every caller shares one config.
    COMMONMARK_OPTIONS = {
      extension: { table: true, autolink: true, tagfilter: true, strikethrough: true,
                   tasklist: true, footnotes: true, header_ids: '' },
      parse: { smart: false },
      render: { unsafe: true }
    }.freeze
    # kramdown's own attribute escaper, the one its HTML converter writes every href and src with.
    KRAMDOWN_HTML = Object.new.extend(Kramdown::Utils::Html).freeze
    # What kramdown-parser-gfm raises on a heading or definition term it cannot build: TypeError gathering its text
    # when a reference is at or past 2**31 (`&#x80000000;`, `&#99999999999999999999;`), in either parse;
    # ArgumentError slugging a heading that holds a surrogate or a code point past U+10FFFF, in the parse with ids.
    SITE_PARSE_ERRORS = [ArgumentError, TypeError].freeze
    # Prepended to one parser instance: the two steps of kramdown's own parse that raise those errors record the
    # line of the element they were working on. Nothing is restated, so the line is the parser's own.
    # ceiling: the hooks name gem methods (update_raw_text, generate_gfm_header_id); if they are renamed, the
    # page is still reported, on line 1, and the line test fails.
    module SiteParseLocator
      attr_reader :failed_line

      def update_raw_text(item)
        super
      rescue *SITE_PARSE_ERRORS
        @failed_line ||= item.options[:location]
        raise
      end

      def generate_gfm_header_id(text)
        super
      rescue *SITE_PARSE_ERRORS
        @failed_line ||= steward_header_location(root, text)
        raise
      end

      private

      # The heading whose own raw_text is being slugged (update_elements passes that very object).
      def steward_header_location(element, text)
        return element.options[:location] if element.type == :header && element.options[:raw_text].equal?(text)

        element.children.each { |child| (line = steward_header_location(child, text)) && (return line) }
        nil
      end
    end
    MARKDOWN_LINK_PATH_MESSAGE = 'a link to a Markdown page that the site\'s relative-links plugin can\'t ' \
                                 'always rewrite — the built page then keeps a broken link; link a page, not an ' \
                                 'image, end the path in a literal .md with no query, and keep the path to ' \
                                 'letters, digits and . _ - ~ / in NFC form, with no leading / or ~ and no .. ' \
                                 'inside a name (non-ASCII letters may be percent-' \
                                 'encoded); write a character reference as the character itself or percent-encoded ' \
                                 '(é or %C3%A9, not &eacute;), and rename a page whose name needs anything else'
    # The page paths the plugin always rewrites intact: letters, marks and digits in any script, and `. _ - ~ /`.
    PLAIN_PAGE_PATH = %r{\A[\p{L}\p{M}\p{N}._~/-]+\z}.freeze
    INVALID_UTF8_MESSAGE = 'not valid UTF-8 — both renderers read the file as UTF-8, so its text and anchors ' \
                           'are not what was written; save it as UTF-8'

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
      rendered_heading_ids(text, raw_html: true).uniq
    end

    # The id of every heading element on the page cmark renders, read with an
    # HTML5 parser rather than scanned out of the source — a heading tag inside a
    # fence, a code span or a comment is not an element there, so it offers no
    # anchor. With raw_html off cmark omits raw HTML altogether, leaving only the
    # ids it generated for markdown headings.
    #
    # A raw heading *without* an id is deliberately not slugged here: GitHub's
    # sanitizer would assign one, but reproducing its full Unicode slugger and
    # duplicate counter is the drift the parser-backed design exists to avoid, and
    # a bare raw <hN> in markdown is an anti-pattern with no instance in the corpus.
    def rendered_heading_ids(text, raw_html:)
      options = COMMONMARK_OPTIONS.merge(render: { unsafe: raw_html })
      html = Commonmarker.to_html(strip_front_matter(text), options: options)
      Nokogiri::HTML5.fragment(html).css(HEADING_TAGS).filter_map { |el| el['id'] }.reject(&:empty?)
    end

    # A file that isn't valid UTF-8, on the line of its first bad byte. Every reader below needs valid text, and
    # neither renderer reads it as written, so it is reported before any of them runs.
    def invalid_encoding(text, source:)
      return if text.valid_encoding?

      # counted on bytes, with a lone CR as a line end, the way the renderers count lines
      line = text.b.gsub(/\r\n?/n, "\n").each_line.find_index do |l|
        !l.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      end
      Rejection.new(source: source, line: line + 1, message: INVALID_UTF8_MESSAGE)
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
      # Every check below parses the page with kramdown, so a page that parse fails on is reported alone.
      begin
        root = document(text, auto_ids: false).root
        document(text)
      rescue *SITE_PARSE_ERRORS => e
        return out << site_parse_failure(text, e, source: source)
      end

      line = 1
      declined = []
      walk(root) do |el|
        line = el.options[:location] || line
        message = unportable_message(el)
        out << Rejection.new(source: source, line: line, message: message) if message
        if unmatchable_page_link?(el, source)
          out << Rejection.new(source: source, line: line, message: MARKDOWN_LINK_PATH_MESSAGE)
        end
        next unless el.type == :text && el.value.match?(RAW_HTML_TAG)

        declined << Rejection.new(source: source, line: line, message: RAW_HTML_MESSAGE)
      end
      out.concat(raw_link_rejections(text, declined, source: source))
      out.concat(divergent_heading_ids(text, source: source))
      out
    end

    # jekyll-relative-links turns a link to a Markdown page into one to the built page, in two passes: one over the
    # markdown source, keyed by the path as written (percent-decoded), and one over the rendered HTML, which only
    # rewrites `<a href="….md">` and `<a href="….md#…">`. It then writes the page's decoded name into the built
    # link, where a character that means something there (`?`, `&`, a parenthesis in markdown) breaks it again. A
    # link that goes wrong stays a .md link or a broken one. Which forms fail depends on both passes' regexes, so
    # rather than model them the rule allows one plain form, which the HTML pass always rewrites intact: a link
    # whose path as written ends in a literal `.md`, has no query, and decodes to letters, marks, digits and
    # `. _ - ~ /` only (PLAIN_PAGE_PATH), in NFC (Jekyll NFC-normalizes the href it builds but keeps a decomposed
    # name's bytes in the file it writes). Anything else is rejected as unverified. An image of a Markdown page is
    # rejected too: rewritten or not, an image whose source is a page is broken.
    def unmatchable_page_link?(element, source)
      href = link_target(element)
      return false if href.nil? || href.empty?

      # external or root-relative as written: the lint leaves those to other checks, as it always has; one only a
      # character reference makes root-relative (`&sol;docs/x.md`) is still judged here
      return false if href.match?(EXTERNAL)

      rendered = site_href(href)

      target = decode(rendered.split(/[?#]/, 2).first.to_s).scrub
      # a NUL can't be a path (Pathname raises on it); build_link reports such a link as missing
      return false if target.include?("\0")
      return false unless Pathname.new(target).cleanpath.to_s.match?(MARKDOWN_EXT)
      return true if element.type == :img || (element.type == :html_element && element.value == 'img')

      path, query = href.split('#', 2).first.to_s.split('?', 2)
      name = decode(path).scrub
      return true if !query.nil? || !path.end_with?('.md') || !name.match?(PLAIN_PAGE_PATH)

      # Where it points, too: a decoded leading `/` or `~` (the plugin roots or expands it), `..` inside a name
      # (`a..b.md` and `a/b.md` build to one page), and a target path, its directories included, not in NFC.
      full = Pathname.new(File.join(File.dirname(source), name)).cleanpath.to_s
      name.start_with?('/', '~') || name.split('/').any? { |seg| seg != '..' && seg.include?('..') } ||
        !full.unicode_normalized?(:nfc)
    end

    # A page the site's parser raises on. kramdown-parser-gfm cannot build a heading or definition term whose text
    # holds a character reference to a surrogate (`&#xD800;`) or past U+10FFFF. Jekyll builds a page with front
    # matter through the same parser, so its build fails on this one (a page without front matter it copies as it
    # is), while GitHub renders it. No anchor into it holds on both, so the page is reported, on the line the
    # parser records for the element it failed on.
    #
    # ceiling: only SITE_PARSE_ERRORS are reported; any other parse error still stops the lint with its
    # backtrace. Add its class there if one turns up.
    def site_parse_failure(text, error, source:)
      site = text.match?(JEKYLL_YAML_HEADER) ? "so Jekyll's build fails on it" : 'so the site cannot render it'
      Rejection.new(source: source, line: site_parse_failure_line(text) || 1,
                    message: "the site's markdown parser fails on this page (#{error.class}: #{error.message}), " \
                             "#{site} — a heading or definition term holding a character reference to a surrogate " \
                             '(&#xD800;) or past U+10FFFF is the known cause; replace or drop the reference')
    end

    # The same parse document runs, on a parser that records where it raised.
    def site_parse_failure_line(text)
      parser = Kramdown::Parser::GFM.send(:new, strip_front_matter(text), {})
      parser.singleton_class.prepend(SiteParseLocator)
      parser.parse
      nil
    rescue *SITE_PARSE_ERRORS
      parser&.failed_line
    end

    # The renderer comparison names the tag's own line, so it is preferred. The
    # tags kramdown visibly left in a text node are the fallback for what the
    # comparison cannot see: a declined tag with no target, or one whose target
    # a tag kramdown did parse happens to share.
    def raw_link_rejections(text, declined, source:)
      unparsed = unparsed_raw_links(text, source: source)
      unparsed.empty? ? declined : unparsed
    end

    # A raw <a>/<img> tag GitHub renders as a link and the site does not — an
    # unquoted attribute value is the usual cause: kramdown declines the tag and
    # prints it as text. Found by asking each renderer what it parsed, since the
    # declined tag may be split across any number of kramdown text nodes: every
    # target cmark reads out of raw HTML has to be one kramdown read out of an
    # HTML element at the same source occurrence too. A parsed tag on another
    # line cannot vouch for a declined tag that happens to share its target.
    def unparsed_raw_links(text, source:)
      site = site_raw_targets(text).tally
      out = []
      walk_cmark(cmark_document(text)) do |node|
        next unless RAW_HTML_NODES.include?(node.type)

        raw_html_targets(node).each do |href, line|
          occurrence = [href, line]
          next site[occurrence] -= 1 if site.fetch(occurrence, 0).positive?

          out << Rejection.new(source: source, line: line, message: RAW_HTML_MESSAGE)
        end
      end
      out
    end

    # [href/src, source line] for every raw <a>/<img> kramdown parsed as an HTML element.
    # kramdown keeps the attribute value as written, so it is run through the
    # same HTML5 parser the cmark side uses to resolve its character references.
    # This is the source read the way cmark reads it, to pair the two renderers'
    # raw tags, not the href a site reader follows (that is site_href).
    def site_raw_targets(text)
      out = []
      walk(document(text).root) do |el|
        attr = HTML_LINK_ATTR[el.value] if el.type == :html_element
        value = el.attr[attr] if attr
        next unless value

        out << [decode_attribute(value), el.options[:location] || 1]
      end
      out
    end

    # An attribute value as the browser reads it, character references resolved.
    def decode_attribute(value)
      Nokogiri::HTML5.fragment(%(<a href="#{value.gsub('"', '&quot;')}">)).at_css('a')['href']
    end

    # A heading the site and GitHub slug differently is an anchor that resolves
    # on one renderer and 404s on the other — a literal tab gives `foo-bar` under
    # kramdown and `foobar` under cmark-gfm. For a doc both publish, neither id is
    # trustworthy, so the document is rejected rather than checked against a set
    # that is wrong on one page. Reported for the included docs only; the excluded
    # ones are read through the cmark ids alone and have no second renderer to
    # disagree with.
    #
    # Only the ids the renderers *generate* are compared. A raw <hN id="..."> is
    # passed through by both with its id as written, so there is nothing to
    # disagree about, and kramdown's header walk never sees it.
    def divergent_heading_ids(text, source:)
      # Normalize after generation, preserving the slugger's duplicate counter.
      # Empty ids offer no usable anchor and cmark omits them too.
      site = heading_ids(text).reject(&:empty?)
      github = rendered_heading_ids(text, raw_html: false)
      return [] if site == github

      [Rejection.new(source: source, line: 1,
                     message: 'heading id the site and GitHub slug differently ' \
                              "(kramdown #{(site - github).inspect}, cmark-gfm #{(github - site).inspect}) " \
                              '— an anchor to it resolves on one renderer and 404s on the other; ' \
                              'rephrase the heading so both slug it the same way')]
    end

    # Both renderers' link sets for one document, deduped by resolved identity so
    # a link they agree on is counted once while one only cmark sees (a reference
    # label they case-fold differently, a raw-HTML target) or resolves elsewhere
    # is kept and checked.
    def merged_links(text, source:)
      dedup_links(links(text, source: source) + links_cmark(text, source: source))
    end

    # Collapse links that resolve to the same target/fragment, keeping the first.
    # A raw <a> and a markdown link to the same file, or an href written two ways
    # that resolve alike, are one broken (or fine) target, not two diagnostics.
    def dedup_links(links)
      seen = {}
      # A nil path names nothing, so two such links don't resolve alike: they are kept apart by href. Every
      # extractor stores the href as its page carries it, so the two renderers' copies of one link merge when
      # both pages carry it alike.
      links.each { |link| seen[[link.source, link.path || [:unnamed, link.href], link.fragment]] ||= link }
      seen.values
    end

    def unportable_message(element)
      return unless element.type == :header && element.attr['id']

      id = element.attr['id']
      "explicit heading id ##{id} — kramdown honours it, GitHub prints the attribute as literal " \
        "text, so ##{id} 404s there; drop it and link the generated slug"
    end

    # Relative markdown links, with the target resolved to a repo-relative path.
    # Read from BOTH renderers and unioned by the caller: kramdown is exact for
    # the site, and cmark-gfm (links_cmark) is exact for the files GitHub renders
    # directly. A link only one of them sees — a reference label they case-fold
    # differently, a raw tag one parses and the other doesn't — is still a link on
    # the page it renders, so the gate has to check it.
    def links(text, source:)
      dir = File.dirname(source)
      out = []
      walk(document(text).root) do |el|
        href = link_target(el)
        next if href.nil?

        href = site_href(href)
        next if href.empty? || href.match?(EXTERNAL)

        out << build_link(href, source, dir, el.options[:location] || 1)
      end
      out
    end

    # The href a reader of the site follows. kramdown keeps a target as written, in a markdown link and a raw tag
    # alike, and writes it out through its own attribute escaper: a well-formed character reference is left for
    # the browser and any other `&` becomes `&amp;`. The browser then reads it with HTML5 rules, so `&eacute;.md`
    # is `é.md`, the unterminated `&eacute.md` is itself, and a reference to a surrogate is one U+FFFD.
    def site_href(value)
      decode_attribute(KRAMDOWN_HTML.escape_html(value, :attribute))
    end

    # The cmark-gfm oracle. commonmarker (comrak) resolves reference links,
    # character references, and nested/image-wrapped links exactly as GitHub's
    # renderer does, so its link set is what a reader on the GitHub file view can
    # actually click. Its urls arrive already entity-decoded (`a&sol;b.md` ->
    # `a/b.md`), and are used as they are: a second pass would turn the literal
    # `a&amp;b.md` from a double-encoded destination into `a&b.md`.
    # Raw <a>/<img> tags are markdown-inert to comrak's link nodes but live links
    # on the GitHub page, so their targets are pulled from the raw HTML too.
    def links_cmark(text, source:)
      dir = File.dirname(source)
      out = []
      walk_cmark(cmark_document(text)) do |node|
        if %i[link image].include?(node.type)
          href = node.url.to_s
        elsif RAW_HTML_NODES.include?(node.type)
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
      raw_html_targets(node).filter_map do |href, line|
        next if href.empty? || href.match?(EXTERNAL)

        build_link(href, source, dir, line)
      end
    end

    # [target, line] for each <a href>/<img src> in a raw-HTML node, read with an
    # HTML5 tokenizer the way the browser reads the page: a commented-out tag is
    # not a link, `data-href` is not `href`, a `>` inside a quoted value does not
    # end the tag, and character references arrive decoded. Quoted and unquoted
    # values are both read — GitHub follows either.
    def raw_html_targets(node)
      start = (node.source_position || {})[:start_line] || 1
      html = node.to_commonmark.gsub(NEUTRALIZED_TAG, '&lt;')
      Nokogiri::HTML5.fragment(html).css(LINK_TAGS).map do |el|
        [el[HTML_LINK_ATTR[el.name]], start + el.line - 1]
      end
    end

    def cmark_document(text)
      Commonmarker.parse(strip_front_matter(text), options: COMMONMARK_OPTIONS)
    end

    def walk_cmark(node, &block)
      yield node
      node.each { |child| walk_cmark(child, &block) }
    end

    # kramdown keeps a footnote's definition as the :footnote element's value, not as its children, and renders
    # it once at the foot of the page, so it is walked once, however often it is referenced.
    def walk(element, seen = {}, &block)
      yield element
      element.children.each { |child| walk(child, seen, &block) }
      return unless element.type == :footnote && element.value && !seen.key?(element.value.object_id)

      seen[element.value.object_id] = true
      walk(element.value, seen, &block)
    end

    def link_target(element)
      case element.type
      when :a then element.attr['href']
      when :img then element.attr['src']
      when :html_element then element.attr[HTML_LINK_ATTR[element.value]]
      end
    end

    # href is the URL as the page carries it, character references already resolved by each extractor
    # (`foo&amp;bar.md` is the file `foo&bar.md`). Percent escapes are the browser's and are decoded per
    # component below, after `#` has done its splitting.
    def build_link(href, source, dir, line)
      target, fragment = href.split('#', 2)
      # A query string is stripped by every renderer before the path is resolved,
      # and percent escapes are decoded, so `foo%20bar.md?v=1` is the tracked
      # file `foo bar.md`.
      # An escape can decode to invalid UTF-8 or a NUL, which no file name holds: the path is nil,
      # and `resolve` reports the link as a missing target.
      rel = decode(target.to_s.split('?', 2).first.to_s)
      path = if !rel.valid_encoding? || rel.include?("\0")
               nil
             elsif rel.empty?
               ''
             else
               Pathname.new(File.join(dir, rel)).cleanpath.to_s
             end
      Link.new(source: source, line: line, href: href, path: path,
               fragment: fragment.nil? || fragment.empty? ? nil : decode(fragment).scrub)
    end

    def decode(str)
      str.b.gsub(PERCENT_ESCAPE) { Regexp.last_match(1).hex.chr }.force_encoding(Encoding::UTF_8)
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
      out = IO.popen(['git', '-C', root, 'ls-files', '-z'], encoding: 'UTF-8', &:read)
      raise "git ls-files failed in #{root}" unless $?&.success?

      out.split("\x00").reject(&:empty?)
    end

    # The set of tracked markdown files _config.yml excludes from the built site.
    # These are rendered by nobody but GitHub, so they are checked against the
    # cmark-gfm oracle rather than kramdown — a link or heading id read with the
    # site's parser would be judged by a renderer that never publishes the file.
    #
    # The matching is Jekyll's own (Jekyll::EntryFilter over Jekyll's own merged
    # config, default excludes included) rather than a copy of it: its glob has no
    # FNM_PATHNAME, an entry is also a bare string prefix, and `include` is matched
    # against an entry's own name — none of which a lookalike matcher kept up with.
    def site_excluded_markdown(root, config_path)
      raw = YAML.safe_load(File.read(config_path, encoding: 'UTF-8')) || {}
      # Jekyll refuses to build from a config it cannot validate — a scalar
      # `exclude`, say — so there is no routing to mirror.
      Jekyll::Configuration[raw].validate
      cfg = Jekyll::Configuration.from(raw)
      site = JekyllSite.new(File.expand_path(root), cfg['exclude'], cfg['include'])
      Set.new(markdown_files(root).reject { |rel| jekyll_reads?(site, rel) })
    rescue Psych::Exception, Jekyll::Errors::InvalidConfigurationError => e
      raise "could not parse #{config_path}: #{e.message}"
    end

    # Jekyll walks the source a directory at a time and filters each directory's
    # entries by name, so a path is read only when every level of it survives:
    # an excluded directory is never entered, whatever `include` says about a
    # file inside it. Only the config-driven half of the filter is asked. Its
    # other rules (dot- and underscore-prefixed names, backups, symlinks) are not
    # routing a config can express, and skipping them keeps such a file checked
    # against both renderers rather than one.
    #
    # The walk is not the only way in: Jekyll's reader also reads every file an
    # `include` entry names outright, wherever it sits.
    def jekyll_reads?(site, rel)
      path = File.join(site.source, rel)
      return true if site.include.any? { |entry| File.expand_path(entry.to_s, site.source) == path }

      dir = ''
      rel.split('/').all? do |name|
        filter = Jekyll::EntryFilter.new(site, dir)
        dir = File.join(dir, name)
        !filter.excluded?(name) || filter.included?(name)
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
      cfg = YAML.safe_load(File.read(config_path, encoding: 'UTF-8')) || {}
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
