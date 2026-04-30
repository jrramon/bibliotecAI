require "test_helper"

class TelegramMessageJobTest < ActiveJob::TestCase
  setup do
    @user = create(:user)
    @message = TelegramMessage.create!(
      user: @user,
      chat_id: 1_234_567,
      update_id: 555,
      text: "hola bot",
      status: :pending
    )
  end

  test "happy path: agent ok → send_message → completed" do
    Telegram::Agent.expects(:call).with(@message)
      .returns(Telegram::Agent::Result.new(ok: true, text: "¡Hola, soy yo!", error: nil))

    Telegram::Client.expects(:send_message)
      .with(chat_id: @message.chat_id, text: "¡Hola, soy yo!")
      .returns({"message_id" => 1})

    TelegramMessageJob.perform_now(@message.id)

    @message.reload
    assert @message.completed?
    assert_equal "¡Hola, soy yo!", @message.bot_reply
    assert_nil @message.error_message
  end

  test "agent failure: surfaces the error to the chat for debugging" do
    Telegram::Agent.expects(:call)
      .returns(Telegram::Agent::Result.new(ok: false, text: nil, error: "claude exited 2: boom"))

    Telegram::Client.expects(:send_message)
      .with { |args| args[:text].include?("Error procesando tu mensaje") && args[:text].include?("boom") }
      .returns({"message_id" => 2})

    TelegramMessageJob.perform_now(@message.id)

    @message.reload
    assert @message.failed?
    assert_match(/boom/, @message.error_message)
  end

  test "send_message error after a successful agent run is captured" do
    Telegram::Agent.expects(:call)
      .returns(Telegram::Agent::Result.new(ok: true, text: "respuesta ok", error: nil))

    Telegram::Client.stubs(:send_message).raises(Telegram::Client::Error.new("network down"))

    assert_nothing_raised do
      TelegramMessageJob.perform_now(@message.id)
    end

    @message.reload
    assert @message.failed?
    assert_match(/send_message failed/, @message.error_message)
  end

  test "non-pending message is left alone (race against another worker)" do
    @message.update!(status: :processing)
    Telegram::Agent.expects(:call).never
    Telegram::Client.expects(:send_message).never

    TelegramMessageJob.perform_now(@message.id)

    assert @message.reload.processing?
  end

  test "missing message is discarded silently" do
    Telegram::Agent.expects(:call).never

    assert_nothing_raised do
      TelegramMessageJob.perform_now(99_999)
    end
  end

  test "unexpected exception still marks the row failed and re-raises" do
    Telegram::Agent.expects(:call).raises(RuntimeError.new("unexpected"))
    Telegram::Client.stubs(:send_message)

    assert_raises(RuntimeError) do
      TelegramMessageJob.perform_now(@message.id)
    end

    @message.reload
    assert @message.failed?
    assert_match(/RuntimeError.*unexpected/, @message.error_message)
  end
end
