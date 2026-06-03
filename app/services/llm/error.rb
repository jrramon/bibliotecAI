module Llm
  # Raised by any provider on a transport/protocol failure. Services rescue
  # generically, so this surfaces the same way the old per-service Error did.
  Error = Class.new(StandardError)
end
