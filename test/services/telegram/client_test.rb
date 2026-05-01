require "test_helper"

class Telegram::ClientTest < ActiveSupport::TestCase
  setup do
    @prev_token = Telegram::Config::BOT_TOKEN
    Telegram::Config.send(:remove_const, :BOT_TOKEN)
    Telegram::Config.const_set(:BOT_TOKEN, "TEST_TOKEN")
  end

  teardown do
    Telegram::Config.send(:remove_const, :BOT_TOKEN)
    Telegram::Config.const_set(:BOT_TOKEN, @prev_token)
  end

  test "send_message returns the parsed result on 2xx" do
    response = ok_response(%({"ok": true, "result": {"message_id": 42}}))
    Net::HTTP.stubs(:start).returns(response)

    result = Telegram::Client.send_message(chat_id: 123, text: "Hola")
    assert_equal 42, result["message_id"]
  end

  test "send_message raises Error on non-2xx" do
    response = error_response(code: "400",
      body: %({"ok": false, "description": "chat not found"}))
    Net::HTTP.stubs(:start).returns(response)

    err = assert_raises(Telegram::Client::Error) do
      Telegram::Client.send_message(chat_id: 999, text: "nope")
    end
    assert_match(/status=400/, err.message)
    assert_match(/chat not found/, err.message)
  end

  test "send_message raises Error on network timeout" do
    Net::HTTP.stubs(:start).raises(Net::OpenTimeout)
    err = assert_raises(Telegram::Client::Error) do
      Telegram::Client.send_message(chat_id: 1, text: "x")
    end
    assert_match(/network/, err.message)
  end

  test "send_message raises when BOT_TOKEN is missing" do
    Telegram::Config.send(:remove_const, :BOT_TOKEN)
    Telegram::Config.const_set(:BOT_TOKEN, "")

    err = assert_raises(Telegram::Client::Error) do
      Telegram::Client.send_message(chat_id: 1, text: "x")
    end
    assert_match(/TOKEN missing/, err.message)
  end

  test "send_chat_action returns true on 2xx" do
    response = ok_response(%({"ok": true, "result": true}))
    Net::HTTP.stubs(:start).returns(response)

    result = Telegram::Client.send_chat_action(chat_id: 123, action: "typing")
    assert_equal true, result
  end

  test "send_chat_action raises Error on non-2xx" do
    response = error_response(code: "400", body: %({"ok": false, "description": "bad"}))
    Net::HTTP.stubs(:start).returns(response)

    err = assert_raises(Telegram::Client::Error) do
      Telegram::Client.send_chat_action(chat_id: 1)
    end
    assert_match(/sendChatAction/, err.message)
  end

  test "chunk returns the text untouched when shorter than the cap" do
    assert_equal ["short"], Telegram::Client.chunk("short")
  end

  test "chunk splits on newline boundaries when possible" do
    text = "para uno\n" + ("a" * 1900) + "\n\npara dos\n" + ("b" * 1900)
    chunks = Telegram::Client.chunk(text, max: 2_000)

    assert chunks.size >= 2
    chunks.each { |c| assert c.length <= 2_000, "chunk too long: #{c.length}" }
    joined = chunks.join
    assert_includes joined, "para uno"
    assert_includes joined, "para dos"
    # Splits should land on newlines, not mid-paragraph: no chunk ends
    # mid-letter when a line break was available before the cap.
    assert chunks.first.end_with?("a") || chunks.first.end_with?("dos"),
      "expected split on a sentence boundary, got: #{chunks.first[-20..]}"
  end

  test "chunk hard-splits a single line longer than the cap" do
    text = "x" * 5_000
    chunks = Telegram::Client.chunk(text, max: 2_000)

    assert_equal 3, chunks.size
    chunks.each { |c| assert c.length <= 2_000 }
    assert_equal 5_000, chunks.join.length
  end

  test "send_message includes parse_mode in the payload when given" do
    captured_body = nil
    ok_resp = ok_response(%({"ok": true, "result": {"message_id": 1}}))
    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |req|
      captured_body = req.body
      ok_resp
    end
    Net::HTTP.stubs(:start).yields(fake_http).returns(ok_resp)

    Telegram::Client.send_message(chat_id: 1, text: "*hola*", parse_mode: "Markdown")

    payload = JSON.parse(captured_body)
    assert_equal "Markdown", payload["parse_mode"]
    assert_equal "*hola*", payload["text"]
  end

  test "send_message falls back to plain text when Telegram rejects parse_mode" do
    bad = error_response(code: "400",
      body: %({"ok": false, "description": "Bad Request: can't parse entities: Character '*' is reserved"}))
    good = ok_response(%({"ok": true, "result": {"message_id": 7}}))

    Net::HTTP.stubs(:start).returns(bad).then.returns(good)

    result = Telegram::Client.send_message(chat_id: 1, text: "*broken_", parse_mode: "Markdown")
    assert_equal 7, result["message_id"]
  end

  test "send_message does not fall back on non-parse errors" do
    Net::HTTP.stubs(:start).returns(error_response(code: "500", body: %({"ok": false, "description": "internal"})))

    assert_raises(Telegram::Client::Error) do
      Telegram::Client.send_message(chat_id: 1, text: "*x*", parse_mode: "Markdown")
    end
  end

  test "chunk drops empty pieces left after stripping" do
    text = "a\n\n\n" + ("b" * 4_500)
    chunks = Telegram::Client.chunk(text, max: 4_000)
    assert chunks.none?(&:empty?)
  end

  private

  def ok_response(body)
    response = mock
    response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
    response.stubs(:body).returns(body)
    response.stubs(:code).returns("200")
    response
  end

  def error_response(code:, body:)
    response = mock
    response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
    response.stubs(:body).returns(body)
    response.stubs(:code).returns(code)
    response
  end
end
