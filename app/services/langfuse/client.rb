require "net/http"
require "json"
require "securerandom"

module Langfuse
  # Minimal client for the Langfuse ingestion API. We hand-build the event
  # payloads instead of pulling in an SDK so the trace / generation data
  # model stays visible in the code — that is the point of this integration.
  #
  # Data model (see https://api.reference.langfuse.com):
  # - A *trace* is one top-level operation ("identify this cover").
  # - A *generation* is one LLM call inside a trace, with model, prompt in,
  #   completion out, token usage and cost.
  # Events are POSTed in a batch to /api/public/ingestion.
  #
  # Tracing is best-effort: a missing config or a Langfuse outage must never
  # break book identification, so `ingest` swallows and logs every failure.
  module Client
    INGESTION_PATH = "/api/public/ingestion"
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5
    OK_STATUS = 207 # ingestion endpoint answers 207 Multi-Status

    module_function

    # Builds a `trace-create` event — the top-level unit of one operation.
    def trace_event(id:, name:, input: nil, output: nil, metadata: {}, user_id: nil, session_id: nil)
      {
        id: SecureRandom.uuid,
        type: "trace-create",
        timestamp: now_iso,
        body: {
          id: id,
          name: name,
          input: input,
          output: output,
          metadata: metadata.presence,
          userId: user_id,
          sessionId: session_id,
          environment: Langfuse::Config::ENVIRONMENT,
          timestamp: now_iso
        }.compact
      }
    end

    # Builds a `generation-create` event — one LLM call within a trace.
    # `level`/`status_message` carry the error state when a call fails.
    # `prompt_name`/`prompt_version` link the generation to a managed
    # prompt in Langfuse — the UI then shows "this output was produced
    # by vN of <name>", which is the whole point of prompt versioning.
    def generation_event(trace_id:, name:, started_at:, ended_at:,
      model: nil, input: nil, output: nil, usage_details: nil, cost_details: nil,
      level: nil, status_message: nil, metadata: {},
      prompt_name: nil, prompt_version: nil)
      {
        id: SecureRandom.uuid,
        type: "generation-create",
        timestamp: now_iso,
        body: {
          id: SecureRandom.uuid,
          traceId: trace_id,
          name: name,
          model: model,
          input: input,
          output: output,
          usageDetails: usage_details,
          costDetails: cost_details,
          startTime: started_at.utc.iso8601(3),
          endTime: ended_at.utc.iso8601(3),
          level: level,
          statusMessage: status_message,
          metadata: metadata.presence,
          promptName: prompt_name,
          promptVersion: prompt_version,
          environment: Langfuse::Config::ENVIRONMENT
        }.compact
      }
    end

    # Builds an `observation-create` event — the general-purpose
    # non-LLM observation. The `type` argument is Langfuse's
    # ObservationType enum: SPAN (plain unit of work), TOOL (an MCP /
    # function call), AGENT (an agent step that contains others),
    # CHAIN, RETRIEVER, EVALUATOR, EMBEDDING, GUARDRAIL. The UI uses
    # the type to pick the icon and offer per-type filters.
    def observation_event(type:, trace_id:, name:, started_at:, ended_at:,
      input: nil, output: nil, level: nil, status_message: nil, metadata: {})
      {
        id: SecureRandom.uuid,
        type: "observation-create",
        timestamp: now_iso,
        body: {
          id: SecureRandom.uuid,
          type: type,
          traceId: trace_id,
          name: name,
          input: input,
          output: output,
          startTime: started_at.utc.iso8601(3),
          endTime: ended_at.utc.iso8601(3),
          level: level,
          statusMessage: status_message,
          metadata: metadata.presence,
          environment: Langfuse::Config::ENVIRONMENT
        }.compact
      }
    end

    # Builds a `score-create` event. Scores are how Langfuse surfaces eval
    # results: each score attaches a numeric value (here 0..1) to a trace
    # (or to a specific observation, via `observation_id:`), with a name
    # that lets the UI aggregate "average shelf_quality per model" across
    # all traces in a dataset run. `data_type: "NUMERIC"` is the default;
    # CATEGORICAL/BOOLEAN exist for non-numeric judgments.
    def score_event(trace_id:, name:, value:, data_type: "NUMERIC",
      observation_id: nil, comment: nil, metadata: {})
      {
        id: SecureRandom.uuid,
        type: "score-create",
        timestamp: now_iso,
        body: {
          id: SecureRandom.uuid,
          traceId: trace_id,
          observationId: observation_id,
          name: name,
          value: value,
          dataType: data_type,
          comment: comment,
          metadata: metadata.presence,
          environment: Langfuse::Config::ENVIRONMENT
        }.compact
      }
    end

    # Maps the `claude -p --output-format json` envelope (everything the CLI
    # returns besides "result") into Langfuse's usageDetails (integer token
    # counts) and costDetails (USD amounts). Defensive: only maps the keys
    # the CLI actually provides.
    def usage_from_claude_envelope(envelope)
      return [nil, nil] unless envelope.is_a?(Hash)

      raw = envelope["usage"]
      usage_details =
        if raw.is_a?(Hash)
          {
            input: raw["input_tokens"],
            output: raw["output_tokens"],
            cache_read: raw["cache_read_input_tokens"],
            cache_creation: raw["cache_creation_input_tokens"]
          }.compact.transform_values(&:to_i).presence
        end

      cost = envelope["total_cost_usd"]
      cost_details = cost ? {"total" => cost.to_f} : nil

      [usage_details, cost_details]
    end

    # POSTs a batch of events. No-op when Langfuse isn't configured; on any
    # transport/HTTP failure it logs and returns nil — never raises.
    def ingest(events)
      events = Array(events).compact
      return if events.empty?
      return unless Langfuse::Config.configured?

      uri = URI.join(Langfuse::Config::HOST, INGESTION_PATH)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(Langfuse::Config::PUBLIC_KEY, Langfuse::Config::SECRET_KEY)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(batch: events)

      response = Net::HTTP.start(uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      if response.code.to_i != OK_STATUS
        Rails.logger.warn("[Langfuse] ingestion HTTP #{response.code}: #{response.body.to_s.truncate(200)}")
      end
      response
    rescue => e
      Rails.logger.warn("[Langfuse] ingestion failed: #{e.class}: #{e.message}")
      nil
    end

    def now_iso
      Time.now.utc.iso8601(3)
    end
  end
end
