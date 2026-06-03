require "json"

module Llm
  # Per-model token pricing so openai_compatible spend can be turned into a USD
  # cost and flow through the existing ClaudeBudget / Langfuse cost path (which
  # both read total_cost_usd). The claude_cli path already gets cost from the
  # CLI envelope.
  #
  # The table is EMPTY by default — until you fill it in, openai_compatible rows
  # carry no cost and count as $0 against MONTHLY_CLAUDE_BUDGET (correct for a
  # flat-rate API like NaN.builders). Configure without a code change via
  # LLM_PRICES, a JSON object of USD-per-1M-tokens, e.g.:
  #
  #   LLM_PRICES='{"qwen3.6":{"input":0.30,"output":0.90},"mimo-v2.5":{"input":0.15,"output":0.60}}'
  module Pricing
    DEFAULT = {}.freeze

    module_function

    def table
      env = ENV["LLM_PRICES"].presence
      return DEFAULT unless env
      DEFAULT.merge(JSON.parse(env))
    rescue JSON::ParserError
      DEFAULT
    end

    # Total USD for a call, or nil when the model's price is unknown (so callers
    # leave total_cost_usd absent rather than asserting a bogus $0).
    def cost_usd(model:, input_tokens:, output_tokens:)
      price = table[model.to_s]
      return nil unless price

      per_million = ->(tokens, rate) { (tokens.to_i / 1_000_000.0) * rate.to_f }
      cost = per_million.call(input_tokens, price["input"]) +
        per_million.call(output_tokens, price["output"])
      cost.round(6)
    end
  end
end
