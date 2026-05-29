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
