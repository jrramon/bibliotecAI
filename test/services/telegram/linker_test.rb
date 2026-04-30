require "test_helper"

class Telegram::LinkerTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @other = create(:user)
    @chat_id = 1_000_000
  end

  def token_for(user, expires_in: 1.day)
    Rails.application.message_verifier(:telegram_link)
      .generate({user_id: user.id}, expires_in: expires_in)
  end

  test "fresh chat_id + valid token binds the user" do
    result = Telegram::Linker.call(token: token_for(@user), chat_id: @chat_id, username: "joserra")

    assert result.ok
    assert_match(/vinculada/i, result.message)
    assert_equal @chat_id, @user.reload.telegram_chat_id
    assert_equal "joserra", @user.telegram_username
  end

  test "already linked to the same user is idempotent" do
    @user.link_telegram!(chat_id: @chat_id, username: "joserra")

    result = Telegram::Linker.call(token: token_for(@user), chat_id: @chat_id, username: "joserra")

    assert result.ok
    assert_match(/ya estaba vinculada/i, result.message)
  end

  test "username refreshed if it changed on Telegram side" do
    @user.link_telegram!(chat_id: @chat_id, username: "old")
    Telegram::Linker.call(token: token_for(@user), chat_id: @chat_id, username: "new")
    assert_equal "new", @user.reload.telegram_username
  end

  test "chat_id already linked to another user is rejected without leaking" do
    @other.link_telegram!(chat_id: @chat_id, username: "other")

    result = Telegram::Linker.call(token: token_for(@user), chat_id: @chat_id, username: "joserra")

    refute result.ok
    assert_match(/otra cuenta/i, result.message)
    refute_match(/#{@other.email}/, result.message)
    # original binding intact
    assert_equal @chat_id, @other.reload.telegram_chat_id
    assert_nil @user.reload.telegram_chat_id
  end

  test "expired token is rejected" do
    expired = token_for(@user, expires_in: -1.minute)
    result = Telegram::Linker.call(token: expired, chat_id: @chat_id)
    refute result.ok
    assert_match(/inválido o expirado/i, result.message)
  end

  test "tampered token is rejected" do
    tampered = token_for(@user) + "garbage"
    result = Telegram::Linker.call(token: tampered, chat_id: @chat_id)
    refute result.ok
    assert_match(/inválido o expirado/i, result.message)
  end

  test "blank token is rejected without raising" do
    result = Telegram::Linker.call(token: "", chat_id: @chat_id)
    refute result.ok
    assert_match(/inválido o expirado/i, result.message)
  end

  test "valid token but user no longer exists is rejected" do
    token = token_for(@user)
    @user.destroy

    result = Telegram::Linker.call(token: token, chat_id: @chat_id)
    refute result.ok
    assert_match(/inválido o expirado/i, result.message)
  end

  test "broadcasts the linked partial so /users/edit refreshes live" do
    Turbo::StreamsChannel.expects(:broadcast_replace_to)
      .with([@user, :telegram_status],
        target: ActionView::RecordIdentifier.dom_id(@user, :telegram_status),
        partial: "users/registrations/telegram_section",
        locals: {user: @user})

    Telegram::Linker.call(token: token_for(@user), chat_id: @chat_id, username: "joserra")
  end
end
