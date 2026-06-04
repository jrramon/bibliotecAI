module Llm
  # Translates the MCP tool registry into the OpenAI function-calling schema so
  # the openai_compatible provider can advertise the same tools the claude CLI
  # reaches over MCP. The MCP inputSchema is already JSON Schema, so this is a
  # direct field mapping.
  module OpenaiTools
    module_function

    def from_registry
      Mcp::Registry.all.map do |tool|
        manifest = tool.manifest
        {
          type: "function",
          function: {
            name: manifest[:name],
            description: manifest[:description],
            parameters: manifest[:inputSchema]
          }
        }
      end
    end
  end
end
