source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[windows jruby]

gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

gem "bootsnap", require: false
gem "thruster", require: false

gem "image_processing", "~> 1.2"
gem "devise", "~> 4.9"
gem "friendly_id", "~> 5.5"
gem "simple_form"
gem "lograge"
gem "rack-attack"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "standard", require: false
  gem "erb_lint", require: false
  gem "strong_migrations"
  gem "factory_bot_rails"
  gem "database_cleaner-active_record"
end

group :development do
  gem "web-console"
  gem "letter_opener_web"
  gem "lefthook", require: false
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "axe-core-capybara"
  gem "mocha"
end
