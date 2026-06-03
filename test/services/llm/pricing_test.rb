require "test_helper"

class Llm::PricingTest < ActiveSupport::TestCase
  test "cost_usd returns nil when the model price is unknown" do
    Llm::Pricing.stubs(:table).returns({})
    assert_nil Llm::Pricing.cost_usd(model: "qwen3.6", input_tokens: 1000, output_tokens: 1000)
  end

  test "cost_usd computes USD from per-1M-token rates" do
    Llm::Pricing.stubs(:table).returns("qwen3.6" => {"input" => 0.30, "output" => 0.90})
    cost = Llm::Pricing.cost_usd(model: "qwen3.6", input_tokens: 1_000_000, output_tokens: 1_000_000)
    assert_in_delta 1.20, cost, 1e-6
  end

  test "table parses LLM_PRICES JSON and falls back to empty on malformed JSON" do
    original = ENV["LLM_PRICES"]
    ENV["LLM_PRICES"] = '{"mimo-v2.5":{"input":0.15,"output":0.6}}'
    assert_equal({"input" => 0.15, "output" => 0.6}, Llm::Pricing.table["mimo-v2.5"])

    ENV["LLM_PRICES"] = "{not json"
    assert_equal({}, Llm::Pricing.table)
  ensure
    ENV["LLM_PRICES"] = original
  end
end
