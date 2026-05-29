require "test_helper"

class Langfuse::ConfigTest < ActiveSupport::TestCase
  # The whole test suite must never reach cloud.langfuse.com — the
  # Docker web container has the keys in env, so an end-to-end agent
  # test would otherwise emit a real trace per run. This invariant is
  # enforced by an early `return false if Rails.env.test?` inside
  # Langfuse::Config.configured?.
  test "configured? is false in test env (so tests never hit Langfuse)" do
    assert Rails.env.test?, "the test suite must run with Rails.env.test?"
    refute Langfuse::Config.configured?,
      "configured? must return false in test even when keys are set"
  end
end
