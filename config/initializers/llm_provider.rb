# LLM provider config — read from ENV. Mirrors Langfuse::Config / Telegram::Config.
#
# Picks, per task, between the `claude` Code CLI (claude_cli, the default —
# subscription auth, host binary) and an OpenAI-compatible HTTP API (nan_api,
# NaN.builders) so the app can run against non-Claude models.
#
#   LLM_PROVIDER          global default: "claude_cli" | "nan_api"
#   LLM_PROVIDER_<TASK>   per-task override (SHELF, COVER, CLASSIFY, TELEGRAM)
#   LLM_MODEL_<TASK>      model id for that task (e.g. qwen3.6, deepseek-v4-flash)
#   NAN_API_KEY           Bearer key for nan_api (sk-…)
#   NAN_BASE_URL          defaults to https://api.nan.builders/v1
module Llm
  module Config
    NAN_API_KEY = ENV["NAN_API_KEY"].to_s
    NAN_BASE_URL = ENV.fetch("NAN_BASE_URL", "https://api.nan.builders/v1")
    NAN_DEFAULT_MODEL = ENV.fetch("LLM_NAN_DEFAULT_MODEL", "qwen3.6")
    TASKS = %i[shelf cover classify telegram].freeze

    module_function

    # Per-task provider, read at call time so per-service overrides take effect.
    def provider_key(task)
      raw = ENV["LLM_PROVIDER_#{task.to_s.upcase}"].presence ||
        ENV["LLM_PROVIDER"].presence || "claude_cli"
      raw.to_sym
    end

    def model_for(task)
      ENV["LLM_MODEL_#{task.to_s.upcase}"].presence
    end

    def claude_model?(model)
      model.to_s.start_with?("claude")
    end

    # Returns [provider_instance, model] for a task.
    #
    # `override_model` (used by the eval, which passes MODELS=…) wins over the
    # configured model and, when it's a non-Claude id, also infers the nan_api
    # provider — so `MODELS=qwen3.6` routes to NaN while `claude-opus-4-8` stays
    # on the CLI within the same eval run.
    def resolve(task, override_model: nil)
      model = override_model.presence || model_for(task)
      key = provider_key(task)
      key = :nan_api if override_model.present? && !claude_model?(override_model)
      model = NAN_DEFAULT_MODEL if key == :nan_api && model.blank?
      [Llm::Provider.for(key), model]
    end

    def configured?(task)
      case provider_key(task)
      when :nan_api then NAN_API_KEY.present?
      else true
      end
    end
  end
end

# Same graceful-degradation warning as Telegram::Config: surface a misconfig
# in production instead of failing a job at call time.
if Rails.env.production?
  Llm::Config::TASKS.each do |task|
    if Llm::Config.provider_key(task) == :nan_api && Llm::Config::NAN_API_KEY.blank?
      Rails.logger.warn("[Llm] task #{task} resolves to nan_api but NAN_API_KEY is blank")
    end
  end
end
