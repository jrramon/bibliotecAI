module Llm
  # Executes a tool call requested by the model during run_agent, in-process,
  # via Mcp::ToolRunner. Returns the string to feed back as the OpenAI `tool`
  # message content. The authenticated user + signed context (e.g. message_id)
  # are bound at construction — never taken from the model's arguments.
  class ToolExecutor
    def initialize(user:, context: {}, trace_id: nil)
      @user = user
      @context = context
      @trace_id = trace_id
    end

    def call(tool_name, arguments)
      result = Mcp::ToolRunner.run(
        tool_name: tool_name,
        arguments: arguments,
        user: @user,
        context: @context,
        trace_id: @trace_id
      )

      case result.kind
      when :ok then JSON.generate(result.output)
      when :tool_error, :unknown then result.message
      else "tool failed: #{result.message}"
      end
    end
  end
end
