module Llm
  # Outcome of a multi-turn agent run (provider#run_agent). Mirrors the shape of
  # Telegram::Agent::Result so the calling service barely changes. tool_names
  # lists every tool the model called across the run (with repeats, in order)
  # so callers can verify a mandatory call actually happened.
  AgentResult = Struct.new(:ok, :text, :error, :usage_envelope, :tool_names, keyword_init: true)
end
