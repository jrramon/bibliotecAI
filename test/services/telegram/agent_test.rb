require "test_helper"

class Telegram::AgentTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @message = TelegramMessage.create!(
      user: @user,
      chat_id: 1_000,
      update_id: 9_001,
      text: "¿qué eres?",
      status: :pending
    )
  end

  test "happy path: parses the result text from the JSON envelope" do
    stub_capture3(stdout: envelope("¡Hola! Soy el bot."), success: true)

    result = Telegram::Agent.call(@message)

    assert result.ok
    assert_equal "¡Hola! Soy el bot.", result.text
    assert_nil result.error
  end

  test "passes the right argv to claude including MCP flags" do
    captured_args = nil
    Open3.stubs(:capture3).with do |*args|
      captured_args = args
      true
    end.returns([envelope("ok"), "", success_status])

    Telegram::Agent.new(@message, claude_bin: "claude").call

    # First arg is the env hash
    assert_kind_of Hash, captured_args[0]
    assert_equal "30000", captured_args[0]["MCP_TIMEOUT"]
    # Then bin + flags
    assert_equal "claude", captured_args[1]
    assert_equal "-p", captured_args[2]
    rest = captured_args[4..]
    assert_includes rest, "--output-format"
    assert_includes rest, "--model"
    assert_includes rest, "claude-haiku-4-5"
    assert_includes rest, "--mcp-config"
    assert_includes rest, "--strict-mcp-config"
    assert_includes rest, "--allowedTools"
    assert_includes rest, "mcp__bibliotecai__*"
    assert_includes rest, "--max-turns"
  end

  test "wraps the user message in <user_message> tags" do
    captured_prompt = nil
    Open3.stubs(:capture3).with do |*args|
      captured_prompt = args[3] # env, bin, "-p", PROMPT, ...
      true
    end.returns([envelope("ok"), "", success_status])

    Telegram::Agent.call(@message)

    assert_match(/<user_message>\s*¿qué eres\?\s*<\/user_message>/, captured_prompt)
  end

  test "writes a per-message MCP config file with the bearer token and tears it down" do
    captured_config_path = nil
    Open3.stubs(:capture3).with do |*args|
      idx = args.index("--mcp-config")
      captured_config_path = args[idx + 1]
      assert File.exist?(captured_config_path), "config file should exist while claude runs"
      cfg = JSON.parse(File.read(captured_config_path))
      bibliotecai = cfg.dig("mcpServers", "bibliotecai")
      assert_equal "http", bibliotecai["type"]
      assert_match(%r{/mcp\z}, bibliotecai["url"])
      assert_match(/\ABearer .+/, bibliotecai.dig("headers", "Authorization"))
      true
    end.returns([envelope("ok"), "", success_status])

    Telegram::Agent.call(@message)

    refute File.exist?(captured_config_path), "config file should be cleaned up after the call"
  end

  test "config file's bearer is a valid mcp_session token for the user" do
    captured_token = nil
    Open3.stubs(:capture3).with do |*args|
      idx = args.index("--mcp-config")
      cfg = JSON.parse(File.read(args[idx + 1]))
      header = cfg.dig("mcpServers", "bibliotecai", "headers", "Authorization")
      captured_token = header.sub(/\ABearer /, "")
      true
    end.returns([envelope("ok"), "", success_status])

    Telegram::Agent.call(@message)

    payload = Rails.application.message_verifier(:mcp_session).verify(captured_token)
    assert_equal @user.id, payload["user_id"] || payload[:user_id]
    assert_equal @message.id, payload["message_id"] || payload[:message_id]
  end

  test "returns failure when claude exits non-zero" do
    stub_capture3(stdout: "", stderr: "boom", success: false, exit_status: 2)

    result = Telegram::Agent.call(@message)

    refute result.ok
    assert_match(/exited 2/, result.error)
    assert_match(/boom/, result.error)
  end

  test "returns failure when envelope reports is_error" do
    body = JSON.dump({"type" => "result", "is_error" => true, "result" => "model overloaded"})
    stub_capture3(stdout: body, success: true)

    result = Telegram::Agent.call(@message)

    refute result.ok
    assert_match(/is_error=true/, result.error)
    assert_match(/model overloaded/, result.error)
  end

  test "returns failure when output is not JSON" do
    stub_capture3(stdout: "this is not json", success: true)

    result = Telegram::Agent.call(@message)

    refute result.ok
    assert_match(/non-JSON/, result.error)
  end

  test "returns failure when result is empty" do
    stub_capture3(stdout: envelope("   "), success: true)

    result = Telegram::Agent.call(@message)

    refute result.ok
    assert_match(/empty result/, result.error)
  end

  test "returns failure on timeout" do
    Open3.stubs(:capture3).raises(Timeout::Error)

    result = Telegram::Agent.call(@message)

    refute result.ok
    assert_match(/timed out/, result.error)
  end

  private

  def envelope(text)
    JSON.dump({"type" => "result", "is_error" => false, "result" => text})
  end

  def stub_capture3(stdout:, stderr: "", success:, exit_status: 0)
    status = success ? success_status : failure_status(exit_status)
    Open3.stubs(:capture3).returns([stdout, stderr, status])
  end

  def success_status
    s = mock
    s.stubs(:success?).returns(true)
    s.stubs(:exitstatus).returns(0)
    s
  end

  def failure_status(code)
    s = mock
    s.stubs(:success?).returns(false)
    s.stubs(:exitstatus).returns(code)
    s
  end
end
