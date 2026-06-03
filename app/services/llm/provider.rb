module Llm
  # Factory for provider instances. Callers usually go through
  # Llm::Config.resolve(task) which picks the key + model from ENV.
  module Provider
    module_function

    def for(key)
      case key.to_sym
      when :claude_cli then Providers::ClaudeCli.new
      when :openai_compatible then Providers::OpenaiCompatible.new
      else raise ArgumentError, "unknown LLM provider: #{key.inspect}"
      end
    end
  end
end
