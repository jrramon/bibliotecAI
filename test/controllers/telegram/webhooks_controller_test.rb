require "test_helper"

class Telegram::WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @prev_secret = Telegram::Config::WEBHOOK_SECRET
    Telegram::Config.send(:remove_const, :WEBHOOK_SECRET)
    Telegram::Config.const_set(:WEBHOOK_SECRET, "test-secret-abc")
  end

  teardown do
    Telegram::Config.send(:remove_const, :WEBHOOK_SECRET)
    Telegram::Config.const_set(:WEBHOOK_SECRET, @prev_secret)
  end

  test "valid secret with a text message replies «Hola desde Biblio» and 200" do
    Telegram::Client.expects(:send_message).with(
      chat_id: 12345,
      text: "Hola desde Biblio"
    ).once

    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(chat_id: 12345, text: "anything"),
      as: :json

    assert_response :ok
  end

  test "invalid secret → 404, no send_message" do
    Telegram::Client.expects(:send_message).never

    post "/telegram/webhook/wrong",
      params: telegram_text_update(chat_id: 999, text: "x"),
      as: :json

    assert_response :not_found
  end

  test "missing message (e.g. callback_query) → no send, still 200" do
    Telegram::Client.expects(:send_message).never

    post "/telegram/webhook/test-secret-abc",
      params: {update_id: 1, callback_query: {id: "abc"}},
      as: :json

    assert_response :ok
  end

  test "Telegram::Client error is swallowed → 200 (so Telegram doesn't retry)" do
    Telegram::Client.stubs(:send_message).raises(Telegram::Client::Error, "boom")

    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(chat_id: 1, text: "x"),
      as: :json

    assert_response :ok
  end

  private

  def telegram_text_update(chat_id:, text:)
    {
      update_id: 100_001,
      message: {
        message_id: 1,
        from: {id: chat_id, is_bot: false, first_name: "Joserra"},
        chat: {id: chat_id, type: "private"},
        date: Time.current.to_i,
        text: text
      }
    }
  end
end
