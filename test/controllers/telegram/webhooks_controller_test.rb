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

  test "valid secret + linked chat with a private text message creates a row, replies, returns 200" do
    user = create(:user)
    user.link_telegram!(chat_id: 12345)

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
    assert_equal user.id, msg.user_id
    assert_equal 12345, msg.chat_id
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

  test "duplicate update_id from linked chat → only one row, only one send" do
    create(:user).link_telegram!(chat_id: 1)
    Telegram::Client.expects(:send_message).once
    payload = telegram_text_update(update_id: 6, chat_id: 1, text: "dup")

    assert_difference -> { TelegramMessage.count }, 1 do
      2.times do
        post "/telegram/webhook/test-secret-abc", params: payload, as: :json
      end
    end
    assert_equal 1, TelegramMessage.where(update_id: 6).count
  end

  test "Telegram::Client error from linked chat is swallowed → 200, but row is still persisted" do
    create(:user).link_telegram!(chat_id: 1)
    Telegram::Client.stubs(:send_message).raises(Telegram::Client::Error, "boom")

    assert_difference -> { TelegramMessage.count }, 1 do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_text_update(update_id: 7, chat_id: 1, text: "x"),
        as: :json
    end
    assert_response :ok
  end

  test "/start <valid_token> binds the user and replies with the linker outcome" do
    user = create(:user)
    token = Rails.application.message_verifier(:telegram_link)
      .generate({user_id: user.id}, expires_in: 1.day)

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:chat_id] == 555 && kwargs[:text].match?(/Cuenta vinculada/i)
    end.once

    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(update_id: 100, chat_id: 555, text: "/start #{token}").tap { |p|
        p[:message][:from][:username] = "joserra"
      },
      as: :json

    assert_response :ok
    assert_equal 555, user.reload.telegram_chat_id
    assert_equal "joserra", user.telegram_username
    msg = TelegramMessage.find_by(update_id: 100)
    assert_equal user.id, msg.user_id
  end

  test "/start <bad_token> replies with linker error and does NOT bind" do
    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/inválido o expirado/i)
    end.once

    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(update_id: 101, chat_id: 666, text: "/start garbage"),
      as: :json

    assert_response :ok
    assert_nil User.find_by(telegram_chat_id: 666)
  end

  test "regular message from already-linked chat populates user_id" do
    user = create(:user)
    user.link_telegram!(chat_id: 777, username: "joserra")

    Telegram::Client.expects(:send_message).once

    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(update_id: 102, chat_id: 777, text: "hola"),
      as: :json

    msg = TelegramMessage.find_by(update_id: 102)
    assert_equal user.id, msg.user_id
  end

  test "regular message from unlinked chat is ignored: NO row, polite reply, log line" do
    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:chat_id] == 888 && kwargs[:text].match?(/vincula tu cuenta/i)
    end.once

    log_io = StringIO.new
    Rails.logger.broadcast_to(Logger.new(log_io))

    assert_no_difference -> { TelegramMessage.count } do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_text_update(update_id: 103, chat_id: 888, text: "hola"),
        as: :json
    end
    assert_response :ok
    assert_match(/unlinked chat=888/, log_io.string)
  ensure
    Rails.logger.stop_broadcasting_to(Logger.new(log_io)) if log_io
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
