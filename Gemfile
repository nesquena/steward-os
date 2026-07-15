source "https://rubygems.org"

# GitHub Pages-compatible Jekyll + the just-the-docs theme.
gem "jekyll", "~> 4.3"
gem "just-the-docs", "~> 0.10"
gem "jekyll-remote-theme"
gem "jekyll-relative-links"

# Windows / JRuby timezone data (harmless elsewhere)
gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]

group :test do
  # Link/anchor/image checker for the built site (CI PR gate + local checks).
  gem "html-proofer", "~> 5.0"
end
