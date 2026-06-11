require "test_helper"

class Llm::Providers::OpenaiCompatibleTest < ActiveSupport::TestCase
  IMAGE = Rails.root.join("test/fixtures/files/eval_shelves/shelf-4.jpg").to_s

  def provider
    Llm::Providers::OpenaiCompatible.new(api_key: "sk-test", base_url: "https://api.test/v1")
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
    p = Llm::Providers::OpenaiCompatible.new(api_key: "", base_url: "https://api.test/v1")
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

  # --- run_agent (tool-calling loop) ---

  class FakeExecutor
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(name, args)
      @calls << [name, args]
      "TOOL_RESULT"
    end
  end

  def tool_call_response
    {
      "choices" => [{
        "message" => {"role" => "assistant", "tool_calls" => [
          {"id" => "t1", "function" => {"name" => "search_books", "arguments" => '{"q":"kokoro"}'}}
        ]},
        "finish_reason" => "tool_calls"
      }],
      "usage" => {"prompt_tokens" => 10, "completion_tokens" => 5}
    }
  end

  def final_response(text = "Encontré 1 libro.")
    {
      "choices" => [{"message" => {"content" => text}, "finish_reason" => "stop"}],
      "usage" => {"prompt_tokens" => 8, "completion_tokens" => 4}
    }
  end

  test "run_agent executes tool calls then returns the final text + summed usage" do
    p = provider
    p.stubs(:post).returns(tool_call_response, final_response)
    executor = FakeExecutor.new

    result = p.run_agent(
      system_text: "sys", user_text: "hola", tools: [], tool_executor: executor,
      model: "qwen3.6", max_turns: 5
    )

    assert result.ok
    assert_equal "Encontré 1 libro.", result.text
    assert_equal [["search_books", {"q" => "kokoro"}]], executor.calls
    assert_equal({"input_tokens" => 18, "output_tokens" => 9}, result.usage_envelope["usage"])
    assert_equal ["search_books"], result.tool_names
  end

  test "run_agent returns empty tool_names when the model answers without calling tools" do
    p = provider
    p.stubs(:post).returns(final_response("He recibido la foto."))

    result = p.run_agent(
      system_text: "sys", user_text: "hola", tools: [], tool_executor: FakeExecutor.new,
      model: "qwen3.6", max_turns: 5
    )

    assert result.ok
    assert_equal [], result.tool_names
  end

  test "run_agent fails after max_turns without a final answer" do
    p = provider
    p.stubs(:post).returns(tool_call_response) # always asks for a tool
    result = p.run_agent(
      system_text: "sys", user_text: "hola", tools: [], tool_executor: FakeExecutor.new,
      model: "qwen3.6", max_turns: 2
    )

    refute result.ok
    assert_match(/max_turns/, result.error)
    assert_equal %w[search_books search_books], result.tool_names
  end
end
