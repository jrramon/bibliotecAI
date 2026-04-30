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
