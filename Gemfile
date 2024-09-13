source "https://rubygems.org"

ruby file: ".ruby-version"

gem "sinatra", github: "sinatra", require: "sinatra/base"
gem "rackup"
gem "puma"

gem "activesupport", require: "active_support/all"
gem "logger"
gem "json"

group :test do
  gem "minitest"
  gem "rack-test"
  gem "webmock", require: "webmock/minitest"
end

