# Global kill-switch for LLM consumption. Sums the rolling-30-day spend across
# the three models that capture it (ShelfPhoto, CoverPhoto, TelegramMessage)
# and compares it to `ENV["MONTHLY_CLAUDE_BUDGET"]` in USD.
#
# Provider-agnostic: it reads total_cost_usd from claude_usage. claude_cli rows
# get it from the CLI envelope; nan_api rows get it from Llm::Pricing when the
# model's price is configured (LLM_PRICES) — otherwise they count as $0.
#
# - When the env var is missing, `exceeded?` always returns false. No env
#   var = no protection (deliberate: dev/test shouldn't trip it, prod opts
#   in by setting the var).
# - When set, jobs that call Claude check it at the top of `perform` and
#   abort with status :failed and a user-facing "presupuesto agotado"
#   message instead of spending more money.
# - The cost calculation is cached for 5 min in `Rails.cache` so the
#   per-job check stays cheap.
class ClaudeBudget
  WINDOW = 30.days
  CACHE_KEY = "claude_budget/rolling_cost_usd"
  CACHE_TTL = 5.minutes
  EXHAUSTED_MESSAGE = "El bibliotecario está descansando este mes (presupuesto Claude agotado). Vuelve más adelante."

  MODELS = {
    "ShelfPhoto" => ClaudeUsageReport::SHELF_ESTIMATE_USD,
    "CoverPhoto" => ClaudeUsageReport::COVER_ESTIMATE_USD,
    "TelegramMessage" => ClaudeUsageReport::TELEGRAM_ESTIMATE_USD
  }.freeze

  def self.exceeded?
    limit = budget_usd
    return false if limit.nil?
    rolling_cost_usd >= limit
  end

  def self.budget_usd
    raw = ENV["MONTHLY_CLAUDE_BUDGET"]
    raw.present? ? raw.to_f : nil
  end

  def self.rolling_cost_usd
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
      since = WINDOW.ago
      MODELS.sum { |model_name, estimate| cost_for(model_name.constantize, since, estimate) }
    end
  end

  def self.cost_for(klass, since, estimate_usd)
    completed = klass.where(status: :completed).where("created_at >= ?", since)
    real = completed.where.not(claude_usage: nil)
      .sum("(claude_usage->>'total_cost_usd')::float").to_f
    estimated = completed.where(claude_usage: nil).count * estimate_usd
    real + estimated
  end
end
