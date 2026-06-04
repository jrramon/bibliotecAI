require "test_helper"

class Llm::ToolExecutorTest < ActiveSupport::TestCase
  setup { @user = create(:user) }

  def executor
    Llm::ToolExecutor.new(user: @user, context: {message_id: 1}, trace_id: "trace-1")
  end

  test "ok result is returned as JSON for the tool message" do
    Mcp::ToolRunner.stubs(:run).returns(Mcp::ToolRunner::Result.new(kind: :ok, output: {found: 2}))
    assert_equal JSON.generate(found: 2), executor.call("search_books", {})
  end

  test "tool_error returns the message so the model can recover" do
    Mcp::ToolRunner.stubs(:run).returns(Mcp::ToolRunner::Result.new(kind: :tool_error, message: "not found"))
    assert_equal "not found", executor.call("remove_from_wishlist", {})
  end

  test "passes the bound user/context/trace through to the runner" do
    Mcp::ToolRunner.expects(:run).with(
      tool_name: "search_books", arguments: {"q" => "x"},
      user: @user, context: {message_id: 1}, trace_id: "trace-1"
    ).returns(Mcp::ToolRunner::Result.new(kind: :ok, output: {}))

    executor.call("search_books", {"q" => "x"})
  end
end
