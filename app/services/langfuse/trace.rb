require "securerandom"

module Langfuse
  # One-call helper that turns a single LLM call into a Langfuse trace with
  # one generation inside it, and ships it. Every Claude-calling service
  # funnels through here so the trace shape stays consistent — this is the
  # "extracted pattern" of the verbose record_trace from slice 0.
  module Trace
    module_function

    # `error_message` nil => success path; a string => the run failed and
    # the generation is recorded at level ERROR with that message.
    # `envelope` is the raw `claude -p` JSON envelope (everything but
    # "result") — token usage and cost are mapped out of it.
    # `session_id` groups several traces (e.g. all turns of one Telegram
    # chat); `user_id` ties the trace to an app User.
    # `input` is the human/domain input shown on the trace (Preview tab)
    # — distinct from `prompt`, which is the full assembled prompt and
    # lands on the generation (Log View).
    # `trace_id` is normally minted here, but callers can pass one in if
    # they need another process (e.g. the MCP server) to attach spans to
    # the same trace.
    def record(trace_name:, generation_name:, started_at:, prompt:,
      trace_id: nil, input: nil, output: nil, envelope: nil,
      error_message: nil, model: nil, metadata: {}, user_id: nil, session_id: nil,
      prompt_name: nil, prompt_version: nil)
      trace_id ||= SecureRandom.uuid
      usage_details, cost_details = Client.usage_from_claude_envelope(envelope)
      recorded_output = error_message ? nil : output

      trace = Client.trace_event(
        id: trace_id,
        name: trace_name,
        input: input,
        output: recorded_output,
        metadata: metadata,
        user_id: user_id,
        session_id: session_id
      )
      generation = Client.generation_event(
        trace_id: trace_id,
        name: generation_name,
        model: model,
        started_at: started_at,
        ended_at: Time.now,
        input: prompt,
        output: recorded_output,
        usage_details: usage_details,
        cost_details: cost_details,
        level: error_message ? "ERROR" : nil,
        status_message: error_message,
        prompt_name: prompt_name,
        prompt_version: prompt_version
      )
      Client.ingest([trace, generation])
    end
  end
end
