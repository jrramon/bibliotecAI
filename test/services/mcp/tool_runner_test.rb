require "test_helper"

class Mcp::ToolRunnerTest < ActiveSupport::TestCase
  setup { @user = create(:user) }

  def fake_tool(&body)
    Class.new do
      define_singleton_method(:call) { |user:, arguments:, context:| body.call(user, arguments, context) }
    end
  end

  test "ok: returns the tool output" do
    Mcp::Registry.stubs(:find).with("t").returns(fake_tool { |_u, args, _c| {echo: args} })

    result = Mcp::ToolRunner.run(tool_name: "t", arguments: {"a" => 1}, user: @user)

    assert_equal :ok, result.kind
    assert_equal({echo: {"a" => 1}}, result.output)
  end

  test "unknown: when no tool matches the name" do
    result = Mcp::ToolRunner.run(tool_name: "does-not-exist", arguments: {}, user: @user)

    assert_equal :unknown, result.kind
    assert_match(/unknown tool/, result.message)
  end

  test "tool_error: argument/validation errors are recoverable" do
    Mcp::Registry.stubs(:find).with("t").returns(fake_tool { raise ArgumentError, "missing title" })

    result = Mcp::ToolRunner.run(tool_name: "t", arguments: {}, user: @user)

    assert_equal :tool_error, result.kind
    assert_equal "missing title", result.message
  end

  test "crash: unexpected errors are caught" do
    Mcp::Registry.stubs(:find).with("t").returns(fake_tool { raise "boom" })

    result = Mcp::ToolRunner.run(tool_name: "t", arguments: {}, user: @user)

    assert_equal :crash, result.kind
  end
end
