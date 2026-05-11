require "test_helper"

class Mcp::Tools::ProcessShelfPhotoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create(:user)
    @library = create(:library, owner: @user, name: "Casa")
    @message = create_message_with_photo(@user, chat_id: 1_111)
  end

  test "stages a ShelfPhoto in the user's default library and enqueues the job" do
    result = nil
    assert_enqueued_with(job: BookIdentificationJob) do
      assert_difference -> { ShelfPhoto.count }, 1 do
        result = call_tool(context: {message_id: @message.id})
      end
    end

    assert result[:ok]
    shelf = ShelfPhoto.find(result[:shelf_photo_id])
    assert_equal @library.id, shelf.library_id
    assert_equal @user.id, shelf.uploaded_by_user_id
    assert_equal @message.chat_id, shelf.telegram_chat_id
    assert shelf.image.attached?
  end

  test "missing message_id returns an error" do
    result = call_tool(context: {})
    refute result[:ok]
    assert_match(/no current telegram message/i, result[:error])
  end

  test "message_id pointing at another user's message is not found" do
    other = create(:user)
    other_msg = create_message_with_photo(other, chat_id: 2_222)

    result = call_tool(context: {message_id: other_msg.id})
    refute result[:ok]
    assert_equal 0, ShelfPhoto.count
  end

  test "message without an attached photo returns an error" do
    msg = TelegramMessage.create!(user: @user, chat_id: 1_111, update_id: 7_777, text: "hola", status: :pending)
    result = call_tool(context: {message_id: msg.id})
    refute result[:ok]
    assert_match(/no photo attached/i, result[:error])
  end

  test "user without any library returns an error and creates nothing" do
    @library.destroy
    assert_no_difference -> { ShelfPhoto.count } do
      result = call_tool(context: {message_id: @message.id})
      refute result[:ok]
      assert_match(/no library/i, result[:error])
    end
  end

  private

  def call_tool(context:, arguments: {})
    Mcp::Tools::ProcessShelfPhoto.call(user: @user, arguments: arguments, context: context)
  end

  def create_message_with_photo(user, chat_id:)
    msg = TelegramMessage.create!(user: user, chat_id: chat_id, update_id: SecureRandom.random_number(1_000_000), text: "", status: :pending)
    msg.photo.attach(
      io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg"), "rb"),
      filename: "telegram_photo.jpg",
      content_type: "image/jpeg"
    )
    msg
  end
end
