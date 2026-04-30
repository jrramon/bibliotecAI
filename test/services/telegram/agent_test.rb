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

  test "passes the right argv to claude" do
    Open3.expects(:capture3).with(
      "claude", "-p", instance_of(String),
      "--output-format", "json",
      "--model", "claude-haiku-4-5"
    ).returns([envelope("ok"), "", success_status])

    Telegram::Agent.new(@message, claude_bin: "claude").call
  end

  test "wraps the user message in <user_message> tags" do
    captured_prompt = nil
    Open3.stubs(:capture3).with do |*args|
      captured_prompt = args[2] # the prompt is the third positional arg after the binary and "-p"
      true
    end.returns([envelope("ok"), "", success_status])

    Telegram::Agent.call(@message)

    assert_match(/<user_message>\s*¿qué eres\?\s*<\/user_message>/, captured_prompt)
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
