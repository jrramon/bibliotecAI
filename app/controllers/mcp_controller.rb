# MCP HTTP transport. Receives JSON-RPC 2.0 requests from the host
# `claude` CLI and delegates them to Mcp::Server. The session is
# authenticated by a short-lived bearer token (TelegramMessageJob mints
# one per Telegram message and embeds it in the --mcp-config file). No
# Devise: the bearer is the only credential.
#
# The token shape is `Rails.application.message_verifier(:mcp_session)`
# generated with {user_id:, message_id:} and `expires_in: 10.minutes`.
# Verifier failure → 401. User no longer exists → 401. Token good but
# wrong shape → 401. We never leak which of these it was.
class McpController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :touch_last_seen!, raise: false

  def handle
    user = authenticate!
    return unless user

    begin
      payload = JSON.parse(request.body.read)
    rescue JSON::ParserError
      return render json: parse_error_envelope, status: :ok
    end

    response = Mcp::Server.call(user: user, payload: payload)

    # JSON-RPC notifications produce no response body. The MCP spec says
    # the server should return 202 Accepted in that case.
    if response.nil?
      head :accepted
    else
      render json: response, status: :ok
    end
  end

  private

  def authenticate!
    header = request.headers["Authorization"].to_s
    token = header.sub(/\ABearer\s+/, "")
    return reject_unauthorized if token.blank?

    payload = Rails.application.message_verifier(:mcp_session).verify(token)
    user_id = payload.is_a?(Hash) ? (payload["user_id"] || payload[:user_id]) : nil
    user = User.find_by(id: user_id)
    return reject_unauthorized unless user

    user
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    reject_unauthorized
  end

  def reject_unauthorized
    render json: {jsonrpc: "2.0", id: nil, error: {code: -32001, message: "unauthorized"}},
      status: :unauthorized
    nil
  end

  def parse_error_envelope
    {jsonrpc: "2.0", id: nil, error: {code: -32700, message: "parse error"}}
  end
end
