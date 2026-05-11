require "test_helper"

class Mcp::Tools::ProcessBookCoverPhotoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create(:user)
    @library = create(:library, owner: @user, name: "Casa")
    @message = create_message_with_photo(@user, chat_id: 1_111)
  end

  test "stages a CoverPhoto in the user's default library and enqueues the job" do
    result = nil
    assert_enqueued_with(job: CoverIdentificationJob) do
      assert_difference -> { CoverPhoto.count }, 1 do
        result = call_tool(context: {message_id: @message.id})
      end
    end

    assert result[:ok]
    cover = CoverPhoto.find(result[:cover_photo_id])
    assert_equal @library.id, cover.library_id
    assert_equal @user.id, cover.uploaded_by_user_id
    assert_equal @message.chat_id, cover.telegram_chat_id
    assert cover.intent_library?
    assert cover.image.attached?
  end

  test "intent: 'wishlist' stores the cover with the wishlist intent" do
    result = call_tool(context: {message_id: @message.id}, arguments: {"intent" => "wishlist"})

    assert result[:ok]
    cover = CoverPhoto.find(result[:cover_photo_id])
    assert cover.intent_wishlist?
    assert_equal "wishlist", result[:intent]
  end

  test "unknown intent falls back to library" do
    result = call_tool(context: {message_id: @message.id}, arguments: {"intent" => "bananas"})
    cover = CoverPhoto.find(result[:cover_photo_id])
    assert cover.intent_library?
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
    assert_match(/no current telegram message/i, result[:error])
    assert_equal 0, CoverPhoto.count
  end

  test "message without an attached photo returns an error" do
    msg = TelegramMessage.create!(user: @user, chat_id: 1_111, update_id: 7_777, text: "hola", status: :pending)
    result = call_tool(context: {message_id: msg.id})
    refute result[:ok]
    assert_match(/no photo attached/i, result[:error])
  end

  test "user without any library returns an error and creates nothing" do
    @library.destroy
    assert_no_difference -> { CoverPhoto.count } do
      result = call_tool(context: {message_id: @message.id})
      refute result[:ok]
      assert_match(/no library/i, result[:error])
    end
  end

  private

  def call_tool(context:, arguments: {})
    Mcp::Tools::ProcessBookCoverPhoto.call(user: @user, arguments: arguments, context: context)
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
