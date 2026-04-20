ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "factory_bot_rails"
require "mocha/minitest"

module ActiveSupport
  class TestCase
    parallelize(workers: 1)

    include FactoryBot::Syntax::Methods
  end
end
