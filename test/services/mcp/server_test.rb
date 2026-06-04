require "test_helper"

class Mcp::ServerTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
  end

  test "initialize returns capabilities and server info" do
    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => {"protocolVersion" => "2024-11-05"}
    })

    assert_equal "2.0", response[:jsonrpc]
    assert_equal 1, response[:id]
    assert_equal "2024-11-05", response[:result][:protocolVersion]
    assert_equal({tools: {}}, response[:result][:capabilities])
    assert_equal "bibliotecai", response[:result][:serverInfo][:name]
  end

  test "tools/list returns the registry manifests" do
    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/list"
    })

    tools = response[:result][:tools]
    assert tools.any? { |t| t[:name] == "list_my_libraries" }
    tools.each do |t|
      assert t[:description].present?
      assert_equal "object", t[:inputSchema][:type]
    end
  end

  test "tools/call invokes the tool and wraps result as text content" do
    create(:library, owner: @user, name: "Casa")

    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => {"name" => "list_my_libraries", "arguments" => {}}
    })

    refute response[:result][:isError]
    text = response[:result][:content].first[:text]
    assert_match(/Casa/, text)
    payload = JSON.parse(text)
    assert_equal 1, payload.size
  end

  test "tools/call with unknown tool returns invalid_params error" do
    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 4,
      "method" => "tools/call",
      "params" => {"name" => "nope"}
    })

    assert_equal(-32602, response[:error][:code])
    assert_match(/unknown tool/, response[:error][:message])
  end

  test "unknown method returns method_not_found" do
    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 5,
      "method" => "tools/banana"
    })

    assert_equal(-32601, response[:error][:code])
  end

  test "notification (no id) returns nil so the controller can 202" do
    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "method" => "notifications/initialized"
    })

    assert_nil response
  end

  test "ping returns empty result" do
    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 6,
      "method" => "ping"
    })

    assert_equal({}, response[:result])
  end

  test "tool that raises ArgumentError surfaces as isError content, not transport error" do
    fake_tool = Class.new(Mcp::Tool) do
      const_set(:NAME, "explodes")
      const_set(:DESCRIPTION, "kaboom")
      const_set(:INPUT_SCHEMA, {type: "object", properties: {}, additionalProperties: false})
      def call = raise(ArgumentError, "bad arg")
    end

    Mcp::Registry.stubs(:find).with("explodes").returns(fake_tool)

    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 7,
      "method" => "tools/call",
      "params" => {"name" => "explodes"}
    })

    assert response[:result][:isError]
    assert_match(/bad arg/, response[:result][:content].first[:text])
  end

  test "tool that crashes unexpectedly returns internal error" do
    fake_tool = Class.new(Mcp::Tool) do
      const_set(:NAME, "crashes")
      const_set(:DESCRIPTION, "kaboom")
      const_set(:INPUT_SCHEMA, {type: "object", properties: {}, additionalProperties: false})
      def call = raise("wat")
    end

    Mcp::Registry.stubs(:find).with("crashes").returns(fake_tool)

    response = Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0",
      "id" => 8,
      "method" => "tools/call",
      "params" => {"name" => "crashes"}
    })

    assert_equal(-32603, response[:error][:code])
  end

  test "emits a Langfuse span for a successful tool call when given a trace_id" do
    fake_tool = Class.new(Mcp::Tool) do
      const_set(:NAME, "echo")
      const_set(:DESCRIPTION, "echoes the input")
      const_set(:INPUT_SCHEMA, {type: "object", properties: {}, additionalProperties: true})
      def call(**) = {"echoed" => true}
    end
    Mcp::Registry.stubs(:find).with("echo").returns(fake_tool)

    captured = nil
    Langfuse::Client.stubs(:ingest).with do |events|
      captured = events
      true
    end

    Mcp::Server.call(user: @user, trace_id: "trace-xyz", payload: {
      "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
      "params" => {"name" => "echo", "arguments" => {"q" => "Asimov"}}
    })

    observation = captured.first
    assert_equal "observation-create", observation[:type]
    assert_equal "SPAN", observation[:body][:type]
    assert_equal "trace-xyz", observation[:body][:traceId]
    assert_equal "mcp::echo", observation[:body][:name]
    assert_equal({"q" => "Asimov"}, observation[:body][:input])
    assert_equal({"echoed" => true}, observation[:body][:output])
  end

  test "does not emit a span when no trace_id is provided (non-Telegram caller)" do
    fake_tool = Class.new(Mcp::Tool) do
      const_set(:NAME, "noop")
      const_set(:DESCRIPTION, "no-op")
      const_set(:INPUT_SCHEMA, {type: "object", properties: {}, additionalProperties: true})
      def call(**) = {}
    end
    Mcp::Registry.stubs(:find).with("noop").returns(fake_tool)
    Langfuse::Client.expects(:ingest).never

    Mcp::Server.call(user: @user, payload: {
      "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
      "params" => {"name" => "noop"}
    })
  end

  test "emits a span at level ERROR when a tool raises ArgumentError" do
    fake_tool = Class.new(Mcp::Tool) do
      const_set(:NAME, "boom")
      const_set(:DESCRIPTION, "raises")
      const_set(:INPUT_SCHEMA, {type: "object", properties: {}, additionalProperties: true})
      def call(**) = raise(ArgumentError, "bad arg")
    end
    Mcp::Registry.stubs(:find).with("boom").returns(fake_tool)

    captured = nil
    Langfuse::Client.stubs(:ingest).with do |events|
      captured = events
      true
    end

    Mcp::Server.call(user: @user, trace_id: "trace-z", payload: {
      "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
      "params" => {"name" => "boom"}
    })

    span = captured.first
    assert_equal "ERROR", span[:body][:level]
    assert_equal "bad arg", span[:body][:statusMessage]
  end
end
