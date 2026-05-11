module Mcp
  # Abstract base for an MCP tool. Subclasses declare their name,
  # description, and JSON Schema input shape, and implement #call —
  # they receive the authenticated User from the session token, never
  # from the arguments themselves. That's the key safety property: a
  # tool can ONLY ever read or mutate data on behalf of the caller
  # derived from the bearer token.
  #
  # `context` carries request-scoped, signed metadata that the tool
  # is allowed to trust — currently `{message_id:}` from the MCP
  # session token, used by photo-processing tools to resolve the
  # current TelegramMessage and access its attached blob without
  # taking the id as an argument (which Claude could hallucinate).
  class Tool
    class << self
      def name = self::NAME
      def description = self::DESCRIPTION
      def input_schema = self::INPUT_SCHEMA

      # Manifest entry returned by tools/list.
      def manifest
        {
          name: name,
          description: description,
          inputSchema: input_schema
        }
      end
    end

    def self.call(user:, arguments: {}, context: {})
      new(user, arguments, context).call
    end

    def initialize(user, arguments, context = {})
      @user = user
      @arguments = arguments || {}
      @context = context || {}
    end

    def call
      raise NotImplementedError
    end
  end
end
