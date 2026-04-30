module Mcp
  # Minimal JSON-RPC 2.0 dispatcher for the MCP methods Claude Code
  # actually calls during a tool-using turn:
  #
  #   - initialize           (handshake)
  #   - notifications/initialized  (no-op, no response — fire-and-forget)
  #   - tools/list           (manifest of available tools)
  #   - tools/call           (run a tool and return its content)
  #   - ping                 (health check)
  #
  # The full MCP spec is bigger (resources, prompts, sampling, …) but we
  # don't expose any of that yet. Anything else returns method-not-found.
  #
  # The User is authenticated by MCPController via the bearer session
  # token and passed in here — never read from the JSON-RPC payload.
  class Server
    PROTOCOL_VERSION = "2024-11-05"
    SERVER_INFO = {name: "bibliotecai", version: "1.0.0"}.freeze

    JSONRPC_ERRORS = {
      parse_error: -32700,
      invalid_request: -32600,
      method_not_found: -32601,
      invalid_params: -32602,
      internal_error: -32603
    }.freeze

    def self.call(user:, payload:)
      new(user).handle(payload)
    end

    def initialize(user)
      @user = user
    end

    # Returns the JSON-RPC response as a Hash. Returns nil for
    # notifications (requests with no id).
    def handle(payload)
      return error(nil, :invalid_request, "expected JSON object") unless payload.is_a?(Hash)

      id = payload["id"]
      method = payload["method"]
      params = payload["params"] || {}

      # Notifications: requests without id. We don't reply.
      return nil if id.nil? && method.to_s.start_with?("notifications/")

      case method
      when "initialize"
        success(id, {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: {tools: {}},
          serverInfo: SERVER_INFO
        })
      when "ping"
        success(id, {})
      when "tools/list"
        success(id, {tools: Registry.all.map(&:manifest)})
      when "tools/call"
        call_tool(id, params)
      else
        error(id, :method_not_found, "method not found: #{method}")
      end
    end

    private

    def call_tool(id, params)
      tool_name = params["name"]
      arguments = params["arguments"] || {}
      tool = Registry.find(tool_name)

      return error(id, :invalid_params, "unknown tool: #{tool_name}") unless tool

      result = tool.call(user: @user, arguments: arguments)
      success(id, {
        content: [{type: "text", text: JSON.generate(result)}],
        isError: false
      })
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      # Tool argument validation / model validation. Surface to the model
      # as a tool error so it can recover, not as a transport error.
      success(id, {
        content: [{type: "text", text: e.message}],
        isError: true
      })
    rescue => e
      Rails.logger.error("[Mcp::Server] tool=#{tool_name} crashed: #{e.class}: #{e.message}")
      error(id, :internal_error, "tool crashed: #{e.class}")
    end

    def success(id, result)
      {jsonrpc: "2.0", id: id, result: result}
    end

    def error(id, code_key, message)
      {
        jsonrpc: "2.0",
        id: id,
        error: {code: JSONRPC_ERRORS.fetch(code_key), message: message}
      }
    end
  end
end
