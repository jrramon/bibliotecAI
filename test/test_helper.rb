ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "factory_bot_rails"
require "mocha/minitest"

module ActiveSupport
  class TestCase
    parallelize(workers: ENV.fetch("PARALLEL_WORKERS", "1").to_i)

    include FactoryBot::Syntax::Methods

    # MemoryStore is global to the process; clear it between tests so a
    # dedupe key or throttle bucket from one test never leaks into the
    # next. Cheap, idempotent, no allocation if already empty.
    setup { Rails.cache.clear }
  end
end
