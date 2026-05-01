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

  test "linked chat text → :pending row + typing chat action, no inline send_message" do
    user = create(:user)
    user.link_telegram!(chat_id: 12345)

    Telegram::Client.expects(:send_chat_action).with(chat_id: 12345, action: "typing").once
    Telegram::Client.expects(:send_message).never

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
    assert_predicate msg, :pending?
    assert_nil msg.bot_reply
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

  test "duplicate update_id from linked chat → only one row, only one chat action" do
    create(:user).link_telegram!(chat_id: 1)
    Telegram::Client.expects(:send_chat_action).once
    Telegram::Client.expects(:send_message).never
    payload = telegram_text_update(update_id: 6, chat_id: 1, text: "dup")

    assert_difference -> { TelegramMessage.count }, 1 do
      2.times do
        post "/telegram/webhook/test-secret-abc", params: payload, as: :json
      end
    end
    assert_equal 1, TelegramMessage.where(update_id: 6).count
  end

  test "Telegram::Client error on chat action is swallowed → 200, row still persisted" do
    create(:user).link_telegram!(chat_id: 1)
    Telegram::Client.stubs(:send_chat_action).raises(Telegram::Client::Error, "boom")

    assert_difference -> { TelegramMessage.count }, 1 do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_text_update(update_id: 7, chat_id: 1, text: "x"),
        as: :json
    end
    assert_response :ok
    assert_predicate TelegramMessage.last, :pending?
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

    Telegram::Client.expects(:send_chat_action).once
    Telegram::Client.expects(:send_message).never

    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(update_id: 102, chat_id: 777, text: "hola"),
      as: :json

    msg = TelegramMessage.find_by(update_id: 102)
    assert_equal user.id, msg.user_id
    assert_predicate msg, :pending?
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

  test "linked chat photo → CoverPhoto created in user's default library, reply confirms" do
    user = create(:user)
    library = create(:library, owner: user, name: "Casa")
    user.link_telegram!(chat_id: 555_555)

    Telegram::Client.expects(:get_file).with(file_id: "FID_BIG").returns({"file_path" => "photos/file_42.jpg"})
    Telegram::Client.expects(:download_file).with(file_path: "photos/file_42.jpg")
      .returns(File.read(Rails.root.join("test/fixtures/files/shelf.jpg"), mode: "rb"))
    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:chat_id] == 555_555 && kwargs[:text].match?(/recibida/i)
    end

    assert_difference -> { CoverPhoto.count }, 1 do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_photo_update(update_id: 200, chat_id: 555_555),
        as: :json
    end

    assert_response :ok
    cover = CoverPhoto.last
    assert_equal library.id, cover.library_id
    assert_equal user.id, cover.uploaded_by_user_id
    assert_equal 555_555, cover.telegram_chat_id
    assert_predicate cover, :pending?
    assert cover.image.attached?
  end

  test "linked chat photo, but user has no library → reply with explanation, no CoverPhoto" do
    user = create(:user)
    user.link_telegram!(chat_id: 666_666)

    Telegram::Client.expects(:get_file).never
    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/biblioteca/i)
    end

    assert_no_difference -> { CoverPhoto.count } do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_photo_update(update_id: 201, chat_id: 666_666),
        as: :json
    end

    assert_response :ok
  end

  test "linked chat photo with wishlist caption → CoverPhoto.intent = :wishlist" do
    user = create(:user)
    create(:library, owner: user)
    user.link_telegram!(chat_id: 999_001)
    Telegram::Client.stubs(:get_file).returns({"file_path" => "p.jpg"})
    Telegram::Client.stubs(:download_file).returns(File.read(Rails.root.join("test/fixtures/files/shelf.jpg"), mode: "rb"))
    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/wishlist/i)
    end

    payload = telegram_photo_update(update_id: 220, chat_id: 999_001)
    payload[:message][:caption] = "para luego"
    post "/telegram/webhook/test-secret-abc", params: payload, as: :json

    assert_predicate CoverPhoto.last, :intent_wishlist?
  end

  test "linked chat photo with no caption → CoverPhoto.intent = :library (default)" do
    user = create(:user)
    create(:library, owner: user)
    user.link_telegram!(chat_id: 999_002)
    Telegram::Client.stubs(:get_file).returns({"file_path" => "p.jpg"})
    Telegram::Client.stubs(:download_file).returns(File.read(Rails.root.join("test/fixtures/files/shelf.jpg"), mode: "rb"))
    Telegram::Client.stubs(:send_message)

    post "/telegram/webhook/test-secret-abc",
      params: telegram_photo_update(update_id: 221, chat_id: 999_002),
      as: :json

    assert_predicate CoverPhoto.last, :intent_library?
  end

  test "linked chat photo with neutral caption → CoverPhoto.intent = :library" do
    user = create(:user)
    create(:library, owner: user)
    user.link_telegram!(chat_id: 999_003)
    Telegram::Client.stubs(:get_file).returns({"file_path" => "p.jpg"})
    Telegram::Client.stubs(:download_file).returns(File.read(Rails.root.join("test/fixtures/files/shelf.jpg"), mode: "rb"))
    Telegram::Client.stubs(:send_message)

    payload = telegram_photo_update(update_id: 222, chat_id: 999_003)
    payload[:message][:caption] = "qué bueno este libro"
    post "/telegram/webhook/test-secret-abc", params: payload, as: :json

    assert_predicate CoverPhoto.last, :intent_library?
  end

  test "linked chat photo, picks the largest resolution from the photo array" do
    user = create(:user)
    create(:library, owner: user)
    user.link_telegram!(chat_id: 777_777)

    Telegram::Client.expects(:get_file).with(file_id: "FID_BIG").returns({"file_path" => "p/big.jpg"})
    Telegram::Client.stubs(:download_file).returns(File.read(Rails.root.join("test/fixtures/files/shelf.jpg"), mode: "rb"))
    Telegram::Client.stubs(:send_message)

    post "/telegram/webhook/test-secret-abc",
      params: telegram_photo_update(update_id: 202, chat_id: 777_777),
      as: :json

    assert_response :ok
  end

  test "linked chat photo, telegram download fails → reply photo failed, no CoverPhoto" do
    user = create(:user)
    create(:library, owner: user)
    user.link_telegram!(chat_id: 888_888)

    Telegram::Client.stubs(:get_file).raises(Telegram::Client::Error, "telegram getFile network: TimeoutError")
    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/no he podido procesar/i)
    end

    assert_no_difference -> { CoverPhoto.count } do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_photo_update(update_id: 203, chat_id: 888_888),
        as: :json
    end

    assert_response :ok
  end

  test "throttled linked user gets a polite reply, no DB row, no Claude work" do
    user = create(:user)
    user.link_telegram!(chat_id: 333_333)
    Telegram::WebhooksController::THROTTLE_LIMIT.times do |i|
      Rails.cache.write(
        "tg:throttle:#{user.id}:#{Time.current.utc.strftime('%Y%m%d%H')}",
        Telegram::WebhooksController::THROTTLE_LIMIT,
        expires_in: 90.minutes
      )
    end

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:chat_id] == 333_333 && kwargs[:text].match?(/límite/i)
    end.once
    Telegram::Client.expects(:send_chat_action).never

    assert_no_difference -> { TelegramMessage.count } do
      post "/telegram/webhook/test-secret-abc",
        params: telegram_text_update(update_id: 300, chat_id: 333_333, text: "hola"),
        as: :json
    end

    assert_response :ok
  end

  test "throttle counts text and photo messages, not /start" do
    user = create(:user)
    create(:library, owner: user)
    user.link_telegram!(chat_id: 444_444)
    Telegram::Client.stubs(:send_chat_action)
    Telegram::Client.stubs(:send_message)
    Telegram::Client.stubs(:get_file).returns({"file_path" => "p.jpg"})
    Telegram::Client.stubs(:download_file).returns(File.read(Rails.root.join("test/fixtures/files/shelf.jpg"), mode: "rb"))

    # 3 messages: text, photo, text
    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(update_id: 401, chat_id: 444_444, text: "uno"), as: :json
    post "/telegram/webhook/test-secret-abc",
      params: telegram_photo_update(update_id: 402, chat_id: 444_444), as: :json
    post "/telegram/webhook/test-secret-abc",
      params: telegram_text_update(update_id: 403, chat_id: 444_444, text: "dos"), as: :json

    bucket_key = "tg:throttle:#{user.id}:#{Time.current.utc.strftime('%Y%m%d%H')}"
    assert_equal 3, Rails.cache.read(bucket_key)
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

  def telegram_photo_update(update_id:, chat_id:)
    {
      update_id: update_id,
      message: {
        message_id: 1,
        from: {id: chat_id, is_bot: false, first_name: "Joserra"},
        chat: {id: chat_id, type: "private"},
        date: Time.current.to_i,
        photo: [
          {file_id: "FID_TINY", file_size: 1_000, width: 80, height: 120},
          {file_id: "FID_MED", file_size: 50_000, width: 320, height: 480},
          {file_id: "FID_BIG", file_size: 250_000, width: 800, height: 1200}
        ]
      }
    }
  end
end
