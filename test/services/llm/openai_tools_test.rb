require "test_helper"

class Llm::OpenaiToolsTest < ActiveSupport::TestCase
  test "maps every MCP tool to an OpenAI function schema" do
    tools = Llm::OpenaiTools.from_registry

    assert_equal Mcp::Registry.all.size, tools.size

    first = tools.first
    manifest = Mcp::Registry.all.first.manifest
    assert_equal "function", first[:type]
    assert_equal manifest[:name], first[:function][:name]
    assert_equal manifest[:description], first[:function][:description]
    assert_equal manifest[:inputSchema], first[:function][:parameters]
  end
end
