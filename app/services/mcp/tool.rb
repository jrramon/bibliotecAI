module Mcp
  # Abstract base for an MCP tool. Subclasses declare their name,
  # description, and JSON Schema input shape, and implement #call(user,
  # arguments) — they receive the authenticated User from the session
  # token, never from the arguments themselves. That's the key safety
  # property: a tool can ONLY ever read or mutate data on behalf of the
  # caller derived from the bearer token.
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

    def self.call(user:, arguments: {})
      new(user, arguments).call
    end

    def initialize(user, arguments)
      @user = user
      @arguments = arguments || {}
    end

    def call
      raise NotImplementedError
    end
  end
end
