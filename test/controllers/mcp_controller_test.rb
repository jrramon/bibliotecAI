require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @token = Rails.application.message_verifier(:mcp_session)
      .generate({user_id: @user.id}, expires_in: 10.minutes)
  end

  test "tools/list with valid bearer returns the registry" do
    post_mcp(token: @token, payload: {jsonrpc: "2.0", id: 1, method: "tools/list"})

    assert_response :ok
    body = JSON.parse(response.body)
    assert body["result"]["tools"].any? { |t| t["name"] == "list_my_libraries" }
  end

  test "tools/call with valid bearer scopes to the user" do
    create(:library, owner: @user, name: "Casa")

    post_mcp(token: @token, payload: {
      jsonrpc: "2.0", id: 2, method: "tools/call",
      params: {name: "list_my_libraries", arguments: {}}
    })

    assert_response :ok
    body = JSON.parse(response.body)
    refute body["result"]["isError"]
    assert_match(/Casa/, body["result"]["content"].first["text"])
  end

  test "missing Authorization header returns 401" do
    post "/mcp",
      params: {jsonrpc: "2.0", id: 1, method: "tools/list"}.to_json,
      headers: {"Content-Type" => "application/json"}

    assert_response :unauthorized
  end

  test "tampered token returns 401" do
    post_mcp(token: @token + "garbage", payload: {jsonrpc: "2.0", id: 1, method: "tools/list"})
    assert_response :unauthorized
  end

  test "expired token returns 401" do
    expired = Rails.application.message_verifier(:mcp_session)
      .generate({user_id: @user.id}, expires_in: -1.minute)

    post_mcp(token: expired, payload: {jsonrpc: "2.0", id: 1, method: "tools/list"})
    assert_response :unauthorized
  end

  test "valid token but user no longer exists returns 401" do
    token = Rails.application.message_verifier(:mcp_session)
      .generate({user_id: @user.id}, expires_in: 10.minutes)
    @user.destroy

    post_mcp(token: token, payload: {jsonrpc: "2.0", id: 1, method: "tools/list"})
    assert_response :unauthorized
  end

  test "malformed JSON returns parse error envelope" do
    post "/mcp",
      params: "not json",
      headers: {"Content-Type" => "application/json", "Authorization" => "Bearer #{@token}"}

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal(-32700, body["error"]["code"])
  end

  test "notification (no id) returns 202 Accepted with no body" do
    post_mcp(token: @token, payload: {jsonrpc: "2.0", method: "notifications/initialized"})
    assert_response :accepted
  end

  private

  def post_mcp(token:, payload:)
    post "/mcp",
      params: payload.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{token}"
      }
  end
end
