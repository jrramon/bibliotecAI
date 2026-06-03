require "test_helper"

class Llm::Providers::NanApiTest < ActiveSupport::TestCase
  IMAGE = Rails.root.join("test/fixtures/files/eval_shelves/shelf-4.jpg").to_s

  def provider
    Llm::Providers::NanApi.new(api_key: "sk-test", base_url: "https://api.test/v1")
  end

  def request(image_paths: [])
    Llm::Request.new(prompt: "identify", image_paths: image_paths,
      model: "qwen3.6", timeout: 60, response_format: :json)
  end

  test "complete maps content to text and OpenAI usage to a claude-shaped envelope" do
    p = provider
    p.stubs(:post).returns(
      "choices" => [{"message" => {"content" => "{\"books\":[]}"}}],
      "usage" => {"prompt_tokens" => 12, "completion_tokens" => 7, "total_tokens" => 19}
    )

    response = p.complete(request)

    assert_equal "{\"books\":[]}", response.text
    assert_equal({"input_tokens" => 12, "output_tokens" => 7}, response.usage_envelope["usage"])
  end

  test "complete attaches images as base64 data URLs" do
    p = provider
    captured = nil
    p.stubs(:post).with do |_path, body, **|
      captured = body
      true
    end.returns("choices" => [{"message" => {"content" => "{}"}}], "usage" => {})

    p.complete(request(image_paths: [IMAGE]))

    content = captured[:messages].first[:content]
    image_block = content.find { |b| b[:type] == "image_url" }
    assert image_block, "expected an image_url content block"
    assert_match %r{\Adata:image/jpeg;base64,}, image_block[:image_url][:url]
    assert_equal({type: "json_object"}, captured[:response_format])
  end

  test "complete raises Llm::Error when the API key is blank" do
    p = Llm::Providers::NanApi.new(api_key: "", base_url: "https://api.test/v1")
    assert_raises(Llm::Error) { p.complete(request) }
  end

  test "complete injects total_cost_usd when the model price is configured" do
    Llm::Pricing.stubs(:table).returns("qwen3.6" => {"input" => 0.30, "output" => 0.90})
    p = provider
    p.stubs(:post).returns(
      "choices" => [{"message" => {"content" => "{}"}}],
      "usage" => {"prompt_tokens" => 1_000_000, "completion_tokens" => 1_000_000}
    )

    response = p.complete(request)

    assert_in_delta 1.20, response.usage_envelope["total_cost_usd"], 1e-6
  end

  test "complete omits total_cost_usd when the model price is unknown" do
    Llm::Pricing.stubs(:table).returns({})
    p = provider
    p.stubs(:post).returns(
      "choices" => [{"message" => {"content" => "{}"}}],
      "usage" => {"prompt_tokens" => 10, "completion_tokens" => 5}
    )

    response = p.complete(request)

    refute response.usage_envelope.key?("total_cost_usd")
  end
end
