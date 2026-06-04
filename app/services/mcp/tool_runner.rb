module Mcp
  # Runs a single MCP tool and emits the Langfuse TOOL observation — the shared
  # core behind both transports: the JSON-RPC Mcp::Server (claude CLI over HTTP)
  # and Llm::ToolExecutor (the in-process OpenAI tool-calling loop). Keeping it
  # here means tool execution + telemetry are identical on both paths.
  module ToolRunner
    # kind: :ok (output set) | :tool_error (recoverable, message set) |
    #       :unknown (no such tool) | :crash (unexpected error)
    Result = Struct.new(:kind, :output, :message, keyword_init: true)

    module_function

    def run(tool_name:, arguments:, user:, context: {}, trace_id: nil)
      tool = Registry.find(tool_name)
      return Result.new(kind: :unknown, message: "unknown tool: #{tool_name}") unless tool

      started_at = Time.now
      begin
        output = tool.call(user: user, arguments: arguments || {}, context: context || {})
        record(tool_name, arguments, started_at, trace_id, output: output)
        Result.new(kind: :ok, output: output)
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        # Argument / model validation — surface to the model as a tool error so
        # it can recover, not as a transport error.
        record(tool_name, arguments, started_at, trace_id, error: e)
        Result.new(kind: :tool_error, message: e.message)
      rescue => e
        Rails.logger.error("[Mcp::ToolRunner] tool=#{tool_name} crashed: #{e.class}: #{e.message}")
        record(tool_name, arguments, started_at, trace_id, error: e)
        Result.new(kind: :crash, message: "tool crashed: #{e.class}")
      end
    end

    # Emits one Langfuse SPAN observation per tool invocation, attached to the
    # turn's trace. No-op without a trace_id (tests / non-traced callers).
    # NOTE: Langfuse only accepts GENERATION | SPAN | EVENT — a "TOOL" type is
    # rejected (400) and silently dropped, so tool calls use SPAN. The name
    # (mcp::<tool>) is what marks them as tools in the UI.
    def record(tool_name, arguments, started_at, trace_id, output: nil, error: nil)
      return unless trace_id

      observation = Langfuse::Client.observation_event(
        type: "SPAN",
        trace_id: trace_id,
        name: "mcp::#{tool_name}",
        started_at: started_at,
        ended_at: Time.now,
        input: arguments,
        output: error ? nil : output,
        level: error ? "ERROR" : nil,
        status_message: error&.message
      )
      Langfuse::Client.ingest([observation])
    end
  end
end
