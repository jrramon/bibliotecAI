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

  test "valid secret with a private text message creates a row, replies, returns 200" do
    Telegram::Client.expects(:send_message).with(
      chat_id: 12345,
      text: "Hola desde Biblio"
    ).once

    assert_difference -> { TelegramMessage.count }, 1 do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_text_update(update_id: 1, chat_id: 12345, text: "anything"),
        as: :json
    end

    assert_response :ok
    msg = TelegramMessage.last
    assert_equal 12345, msg.chat_id
    assert_equal 1, msg.update_id
    assert_equal "anything", msg.text
    assert_predicate msg, :completed?
    assert_equal "Hola desde Biblio", msg.bot_reply
  end

  test "invalid secret → 404, no row, no send" do
    Telegram::Client.expects(:send_message).never
    assert_no_difference -> { TelegramMessage.count } do
      post "/telegram/webhook/wrong",
        params: telegram_text_update(update_id: 2, chat_id: 999, text: "x"),
        as: :json
    end
    assert_response :not_found
  end

  test "missing message (e.g. callback_query) → 200, no row, no send" do
    Telegram::Client.expects(:send_message).never
    assert_no_difference -> { TelegramMessage.count } do
      post "/telegram/webhook/test-secret-abc",
        params: {update_id: 3, callback_query: {id: "abc"}},
        as: :json
    end
    assert_response :ok
  end

  test "group chat → 200, no row, no send" do
    Telegram::Client.expects(:send_message).never
    payload = telegram_text_update(update_id: 4, chat_id: -555, text: "hola grupo")
    payload[:message][:chat][:type] = "group"

    assert_no_difference -> { TelegramMessage.count } do
      post "/telegram/webhook/test-secret-abc", params: payload, as: :json
    end
    assert_response :ok
  end

  test "supergroup → 200, no row, no send" do
    Telegram::Client.expects(:send_message).never
    payload = telegram_text_update(update_id: 5, chat_id: -666, text: "x")
    payload[:message][:chat][:type] = "supergroup"

    assert_no_difference -> { TelegramMessage.count } do
      post "/telegram/webhook/test-secret-abc", params: payload, as: :json
    end
    assert_response :ok
  end

  test "duplicate update_id → only one row, only one send" do
    Telegram::Client.expects(:send_message).once
    payload = telegram_text_update(update_id: 6, chat_id: 1, text: "dup")

    assert_difference -> { TelegramMessage.count }, 1 do
      2.times do
        post "/telegram/webhook/test-secret-abc", params: payload, as: :json
      end
    end
    assert_equal 1, TelegramMessage.where(update_id: 6).count
  end

  test "Telegram::Client error is swallowed → 200, but row is still persisted" do
    Telegram::Client.stubs(:send_message).raises(Telegram::Client::Error, "boom")

    assert_difference -> { TelegramMessage.count }, 1 do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_text_update(update_id: 7, chat_id: 1, text: "x"),
        as: :json
    end
    assert_response :ok
  end

  test "missing update_id → 200, no row, no send" do
    Telegram::Client.expects(:send_message).never
    assert_no_difference -> { TelegramMessage.count } do
      post "/telegram/webhook/test-secret-abc",
        params: {message: {chat: {id: 1, type: "private"}, text: "x"}},
        as: :json
    end
    assert_response :ok
  end

  private

  def telegram_text_update(update_id:, chat_id:, text:)
    {
      update_id: update_id,
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
