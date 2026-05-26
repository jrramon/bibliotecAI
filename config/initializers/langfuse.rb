# Langfuse config — read from ENV.
#
# - LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY: project API keys from
#   cloud.langfuse.com (Settings → API Keys). Format "pk-lf-..." / "sk-lf-...".
# - LANGFUSE_HOST: ingestion host. Defaults to Langfuse Cloud.
# - LANGFUSE_TRACING_ENVIRONMENT: tags every trace so dev and prod traffic
#   stay separable inside a single Langfuse project. Defaults to Rails.env.
#
# Tracing is best-effort observability: when the keys are absent the whole
# integration is a silent no-op (`configured?` is false), so the app boots
# and identifies books exactly as before. Same degradation as Telegram::Config.
module Langfuse
  module Config
    PUBLIC_KEY = ENV["LANGFUSE_PUBLIC_KEY"].to_s
    SECRET_KEY = ENV["LANGFUSE_SECRET_KEY"].to_s
    HOST = ENV.fetch("LANGFUSE_HOST", "https://cloud.langfuse.com")
    ENVIRONMENT = ENV.fetch("LANGFUSE_TRACING_ENVIRONMENT", Rails.env.to_s)

    def self.configured?
      # Tests must never hit Langfuse, even when the env vars happen to
      # be set (the Docker web container has them in dev). The early
      # return makes the integration a no-op under Rails.env.test? so
      # the suite stays offline and the cloud project stays clean.
      return false if Rails.env.test?
      PUBLIC_KEY.present? && SECRET_KEY.present?
    end
  end
end
