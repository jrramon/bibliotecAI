require "test_helper"

class Langfuse::PromptTest < ActiveSupport::TestCase
  setup do
    Rails.cache.delete(Langfuse::Prompt.cache_key("cover-identification"))
  end

  teardown do
    Rails.cache.delete(Langfuse::Prompt.cache_key("cover-identification"))
  end

  test "compile substitutes {{var}} placeholders" do
    prompt = Langfuse::Prompt.new(name: "p", version: 1, body: "hello {{name}}")
    assert_equal "hello world", prompt.compile(name: "world")
  end

  test "compile leaves unknown placeholders alone instead of swallowing them" do
    prompt = Langfuse::Prompt.new(name: "p", version: 1, body: "hi {{name}}, {{missing}}")
    out = prompt.compile(name: "Ana")
    assert_equal "hi Ana, {{missing}}", out
  end

  test "compile accepts both string and symbol keys" do
    prompt = Langfuse::Prompt.new(name: "p", version: 1, body: "{{x}}-{{y}}")
    assert_equal "1-2", prompt.compile("x" => "1", :y => "2")
  end

  test "fallback? is true for a prompt without a Langfuse version" do
    fallback = Langfuse::Prompt.new(name: "p", version: nil, body: "...")
    fetched = Langfuse::Prompt.new(name: "p", version: 3, body: "...")
    assert fallback.fallback?
    refute fetched.fallback?
  end

  test "get returns the local fallback when Langfuse isn't configured" do
    Langfuse::Config.stubs(:configured?).returns(false)
    Net::HTTP.expects(:start).never

    prompt = Langfuse::Prompt.get("cover-identification", fallback: "FALLBACK BODY")
    assert_equal "FALLBACK BODY", prompt.body
    assert prompt.fallback?
  end

  test "get returns a Prompt from the API when reachable" do
    Langfuse::Config.stubs(:configured?).returns(true)
    fake = mock
    fake.stubs(:code).returns("200")
    fake.stubs(:body).returns(JSON.generate(
      "name" => "cover-identification", "version" => 7, "prompt" => "{{image_path}}"
    ))
    Net::HTTP.expects(:start).returns(fake)

    prompt = Langfuse::Prompt.get("cover-identification", fallback: "ignored")
    assert_equal "{{image_path}}", prompt.body
    assert_equal 7, prompt.version
    refute prompt.fallback?
  end

  test "get falls back to the local body when the API returns non-200" do
    Langfuse::Config.stubs(:configured?).returns(true)
    fake = mock
    fake.stubs(:code).returns("404")
    fake.stubs(:body).returns("not found")
    Net::HTTP.expects(:start).returns(fake)

    prompt = Langfuse::Prompt.get("cover-identification", fallback: "LOCAL")
    assert_equal "LOCAL", prompt.body
    assert prompt.fallback?
  end

  test "get falls back to the local body when the network raises" do
    Langfuse::Config.stubs(:configured?).returns(true)
    Net::HTTP.stubs(:start).raises(Errno::ECONNREFUSED)

    prompt = Langfuse::Prompt.get("cover-identification", fallback: "LOCAL")
    assert_equal "LOCAL", prompt.body
    assert prompt.fallback?
  end

  test "get caches the fetched prompt across calls within the TTL" do
    Langfuse::Config.stubs(:configured?).returns(true)
    fake = mock
    fake.stubs(:code).returns("200")
    fake.stubs(:body).returns(JSON.generate("version" => 2, "prompt" => "v2"))
    Net::HTTP.expects(:start).once.returns(fake)

    a = Langfuse::Prompt.get("cover-identification", fallback: "L")
    b = Langfuse::Prompt.get("cover-identification", fallback: "L")
    assert_equal "v2", a.body
    assert_equal "v2", b.body
  end
end
