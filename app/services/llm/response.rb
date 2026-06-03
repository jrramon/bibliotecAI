module Llm
  # Normalized single-shot response.
  #
  # - text:           the assistant's text output (inner content). For the
  #                   claude CLI this is the envelope's "result" string.
  # - usage_envelope: a CLAUDE-SHAPED hash, e.g.
  #                   {"usage" => {"input_tokens" => …, "output_tokens" => …},
  #                    "total_cost_usd" => …}. Keeping this shape lets
  #                   Langfuse::Client.usage_from_claude_envelope and the
  #                   claude_usage column work unchanged for every provider.
  Response = Struct.new(:text, :usage_envelope, keyword_init: true)
end
