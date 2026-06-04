require "test_helper"

class ClaudeBookIdentifierTest < ActiveSupport::TestCase
  setup do
    @shelf_photo = create(:shelf_photo)
  end

  test "passes --model to claude when model: kwarg is given" do
    captured_args = nil
    Open3.stubs(:capture3).with do |*args|
      captured_args = args
      true
    end.returns([envelope, "", success_status])

    ClaudeBookIdentifier.new(@shelf_photo, model: "claude-sonnet-4-6").call

    assert_includes captured_args, "--model"
    assert_includes captured_args, "claude-sonnet-4-6"
  end

  test "omits --model when no model is given (default behavior)" do
    captured_args = nil
    Open3.stubs(:capture3).with do |*args|
      captured_args = args
      true
    end.returns([envelope, "", success_status])

    ClaudeBookIdentifier.new(@shelf_photo).call

    refute_includes captured_args, "--model"
  end

  test "openai_compatible path: prompt references the attached image, not a tmp file path" do
    captured = nil
    fake = Object.new
    fake.define_singleton_method(:inline_images?) { true }
    fake.define_singleton_method(:complete) do |request|
      captured = request
      Llm::Response.new(text: '{"image_width":1,"image_height":1,"books":[],"unidentified":[]}', usage_envelope: nil)
    end
    Llm::Config.stubs(:resolve).with(:shelf, override_model: nil).returns([fake, "qwen3.6"])

    ClaudeBookIdentifier.new(@shelf_photo).call

    refute_includes captured.prompt, "tmp/shelf_photos"
    assert_includes captured.prompt, "attached directly to this message"
    # The bytes still travel via image_paths even though the prompt has no path.
    assert_equal 1, captured.image_paths.size
  end

  test "surfaces a provider failure as ClaudeBookIdentifier::Error (job retry contract)" do
    Open3.stubs(:capture3).returns(["", "boom", Struct.new(:success?, :exitstatus).new(false, 1)])

    assert_raises(ClaudeBookIdentifier::Error) do
      ClaudeBookIdentifier.new(@shelf_photo).call
    end
  end

  private

  def envelope
    JSON.dump({
      "result" => JSON.dump({
        "image_width" => 1000,
        "image_height" => 800,
        "books" => [],
        "unidentified" => []
      }),
      "usage" => {}
    })
  end

  def success_status
    Struct.new(:success?, :exitstatus).new(true, 0)
  end
end
