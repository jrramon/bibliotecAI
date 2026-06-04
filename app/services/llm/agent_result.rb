module Llm
  # Outcome of a multi-turn agent run (provider#run_agent). Mirrors the shape of
  # Telegram::Agent::Result so the calling service barely changes.
  AgentResult = Struct.new(:ok, :text, :error, :usage_envelope, keyword_init: true)
end
