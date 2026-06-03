ENV["RAILS_ENV"] ||= "test"
# Pin the LLM provider so the suite never resolves to openai_compatible (and
# never hits the network), even if the dev env has LLM_PROVIDER set. HTTP-provider
# tests instantiate Llm::Providers::OpenaiCompatible directly with a fake key.
ENV["LLM_PROVIDER"] = "claude_cli"
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
