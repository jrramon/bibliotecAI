require "test_helper"

class TelegramLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @prev_username = Telegram::Config::BOT_USERNAME
    Telegram::Config.send(:remove_const, :BOT_USERNAME)
    Telegram::Config.const_set(:BOT_USERNAME, "BiblioDevBot")

    @user = create(:user, password: "supersecret123")
    sign_in_via_devise(@user)
  end

  teardown do
    Telegram::Config.send(:remove_const, :BOT_USERNAME)
    Telegram::Config.const_set(:BOT_USERNAME, @prev_username)
  end

  test "POST creates a token, redirects, exposes deep link AND raw /start command" do
    post telegram_link_path
    assert_redirected_to edit_user_registration_path

    deep_link = flash[:telegram_deep_link]
    start_cmd = flash[:telegram_start_command]
    assert_match %r{\Ahttps://t\.me/BiblioDevBot\?start=}, deep_link
    assert_match %r{\A/start \S+\z}, start_cmd

    # Same token in both, decodes to the user_id
    token = deep_link.split("start=").last
    assert_equal "/start #{token}", start_cmd
    payload = Rails.application.message_verifier(:telegram_link).verify(token)
    assert_equal @user.id, payload["user_id"]
  end

  test "DELETE unlinks the current user" do
    @user.link_telegram!(chat_id: 12345, username: "joserra")

    delete telegram_link_path
    assert_redirected_to edit_user_registration_path

    assert_nil @user.reload.telegram_chat_id
    assert_nil @user.telegram_username
  end

  test "POST without auth redirects to sign in" do
    delete destroy_user_session_path
    post telegram_link_path
    assert_redirected_to new_user_session_path
  end

  private

  def sign_in_via_devise(user)
    post user_session_path, params: {user: {email: user.email, password: "supersecret123"}}
  end
end
