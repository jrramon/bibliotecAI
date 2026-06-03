# LLM provider config — read from ENV. Mirrors Langfuse::Config / Telegram::Config.
#
# Picks, per task, between the `claude` Code CLI (claude_cli, the default —
# subscription auth, host binary) and a generic OpenAI-compatible HTTP API
# (openai_compatible — NaN.builders, OpenRouter, a local vLLM, …) so the app
# can run against non-Claude models.
#
#   LLM_PROVIDER          global default: "claude_cli" | "openai_compatible"
#   LLM_PROVIDER_<TASK>   per-task override (SHELF, COVER, CLASSIFY, TELEGRAM)
#   LLM_MODEL_<TASK>      model id for that task (e.g. qwen3.6, deepseek-v4-flash)
#   LLM_API_KEY           Bearer key for openai_compatible (sk-…)
#   LLM_API_BASE_URL      OpenAI-compatible base URL (defaults to NaN.builders)
#   LLM_API_MODEL         default model when a task is on openai_compatible
module Llm
  module Config
    API_KEY = ENV["LLM_API_KEY"].to_s
    API_BASE_URL = ENV.fetch("LLM_API_BASE_URL", "https://api.nan.builders/v1")
    API_DEFAULT_MODEL = ENV.fetch("LLM_API_MODEL", "qwen3.6")
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
    # configured model and, when it's a non-Claude id, also infers the
    # openai_compatible provider — so `MODELS=qwen3.6` routes to the HTTP API
    # while `claude-opus-4-8` stays on the CLI within the same eval run.
    def resolve(task, override_model: nil)
      model = override_model.presence || model_for(task)
      key = provider_key(task)
      key = :openai_compatible if override_model.present? && !claude_model?(override_model)
      model = API_DEFAULT_MODEL if key == :openai_compatible && model.blank?
      [Llm::Provider.for(key), model]
    end

    def configured?(task)
      case provider_key(task)
      when :openai_compatible then API_KEY.present?
      else true
      end
    end
  end
end

# Same graceful-degradation warning as Telegram::Config: surface a misconfig
# in production instead of failing a job at call time.
if Rails.env.production?
  Llm::Config::TASKS.each do |task|
    if Llm::Config.provider_key(task) == :openai_compatible && Llm::Config::API_KEY.blank?
      Rails.logger.warn("[Llm] task #{task} resolves to openai_compatible but LLM_API_KEY is blank")
    end
  end
end
