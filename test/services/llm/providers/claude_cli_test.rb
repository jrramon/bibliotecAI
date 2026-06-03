require "test_helper"

class Llm::Providers::ClaudeCliTest < ActiveSupport::TestCase
  def success_status
    Struct.new(:success?, :exitstatus).new(true, 0)
  end

  test "complete builds argv with --add-dir + --model and splits the envelope" do
    captured = nil
    Open3.stubs(:capture3).with do |*args|
      captured = args
      true
    end.returns([JSON.dump("result" => "{\"ok\":true}", "usage" => {"input_tokens" => 1}), "", success_status])

    response = Llm::Providers::ClaudeCli.new(claude_bin: "claude").complete(
      Llm::Request.new(prompt: "p", image_paths: ["/tmp/imgs/a.jpg"],
        model: "claude-opus-4-8", timeout: 30, response_format: :json)
    )

    assert_includes captured, "--model"
    assert_includes captured, "claude-opus-4-8"
    assert_includes captured, "--add-dir"
    assert_includes captured, "/tmp/imgs"
    assert_equal "{\"ok\":true}", response.text
    assert_equal({"input_tokens" => 1}, response.usage_envelope["usage"])
  end

  test "complete omits --model when none is given" do
    captured = nil
    Open3.stubs(:capture3).with do |*args|
      captured = args
      true
    end.returns([JSON.dump("result" => "{}", "usage" => {}), "", success_status])

    Llm::Providers::ClaudeCli.new(claude_bin: "claude").complete(
      Llm::Request.new(prompt: "p", image_paths: [], model: nil, timeout: 30, response_format: :json)
    )

    refute_includes captured, "--model"
  end

  test "complete raises Llm::Error when the CLI exits non-zero" do
    Open3.stubs(:capture3).returns(["", "boom", Struct.new(:success?, :exitstatus).new(false, 2)])

    assert_raises(Llm::Error) do
      Llm::Providers::ClaudeCli.new(claude_bin: "claude").complete(
        Llm::Request.new(prompt: "p", image_paths: [], model: nil, timeout: 30, response_format: :json)
      )
    end
  end
end
