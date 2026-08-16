source "https://rubygems.org"

# GitHub Pages-compatible Jekyll + the just-the-docs theme.
gem "jekyll", "~> 4.3"
gem "just-the-docs", "~> 0.10"
gem "jekyll-remote-theme"
gem "jekyll-relative-links"

# The markdown parser Jekyll renders with. bin/anchor-lint reads links and
# heading ids straight out of it rather than predicting them, so it depends on
# these directly and not just through jekyll.
gem "kramdown", "~> 2.5"
gem "kramdown-parser-gfm", "~> 1.1"

# The cmark-gfm renderer GitHub uses for the files _config.yml excludes from the
# built site (README/CONTRIBUTING/SECURITY/skills). bin/anchor-lint reads their
# links from this second oracle so a reference label the two renderers case-fold
# differently, or a target GitHub decodes a character reference in, is still
# checked. Ships as a precompiled platform gem, so CI needs no C/Rust toolchain.
gem "commonmarker", "~> 2.0"

# Windows / JRuby timezone data (harmless elsewhere)
gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]

group :test do
  # Link/anchor/image checker for the built site (CI PR gate + local checks).
  gem "html-proofer", "~> 5.0"

  # test/*_test.rb. Ruby ships minitest as a bundled gem, but under `bundle exec`
  # the require shim only honours what the Gemfile declares, so the suite cannot
  # load it undeclared.
  gem "minitest", "~> 5.0"
end
