require "test_helper"

class Telegram::NotifyIdentifiedShelfTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user, name: "Casa")
    @chat_id = 9_999_999
  end

  test "completed with multiple high-confidence entries summarizes and links to the web" do
    shelf = build_shelf(status: :completed, telegram_chat_id: @chat_id, payload: payload_with(
      [
        {"title" => "Kokoro", "confidence" => 0.9},
        {"title" => "Norwegian Wood", "confidence" => 0.85},
        {"title" => "1Q84", "confidence" => 0.8},
        {"title" => "Beloved", "confidence" => 0.7}
      ],
      below: [{"title" => "Borroso", "confidence" => 0.2}]
    ))

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:chat_id] == @chat_id &&
        kwargs[:text].include?("4 libros") &&
        kwargs[:text].include?("Casa") &&
        kwargs[:text].include?("Kokoro") &&
        kwargs[:text].include?("y 1 más") &&
        kwargs[:text].include?("1 sin identificar") &&
        kwargs[:text].include?("/libraries/#{@library.id}/shelf_photos/#{shelf.id}")
    end

    Telegram::NotifyIdentifiedShelf.call(shelf)
  end

  test "completed with no high-confidence entries explains and links to the web" do
    shelf = build_shelf(status: :completed, telegram_chat_id: @chat_id, payload: payload_with(
      [],
      below: [{"title" => "Algo", "confidence" => 0.2}]
    ))

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/no identifiqué/i) &&
        kwargs[:text].include?("/libraries/#{@library.id}/shelf_photos/#{shelf.id}")
    end

    Telegram::NotifyIdentifiedShelf.call(shelf)
  end

  test "completed with all entries above threshold uses singular wording for one book" do
    shelf = build_shelf(status: :completed, telegram_chat_id: @chat_id, payload: payload_with(
      [{"title" => "Solo", "confidence" => 0.9}]
    ))

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].include?("1 libro") &&
        !kwargs[:text].include?("1 libros") &&
        !kwargs[:text].match?(/sin identificar/i)
    end

    Telegram::NotifyIdentifiedShelf.call(shelf)
  end

  test "failed shelf replies with a generic error message" do
    shelf = build_shelf(status: :failed, telegram_chat_id: @chat_id, payload: nil, error: "boom")

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/error/i) && kwargs[:text].match?(/estanter/i)
    end

    Telegram::NotifyIdentifiedShelf.call(shelf)
  end

  test "no chat_id (web upload) is a no-op" do
    shelf = build_shelf(status: :completed, telegram_chat_id: nil, payload: payload_with(
      [{"title" => "X", "confidence" => 0.9}]
    ))

    Telegram::Client.expects(:send_message).never

    Telegram::NotifyIdentifiedShelf.call(shelf)
  end

  private

  def build_shelf(status:, telegram_chat_id:, payload:, error: nil)
    shelf = ShelfPhoto.new(
      library: @library,
      uploaded_by_user: @user,
      telegram_chat_id: telegram_chat_id,
      status: status,
      claude_raw_response: payload,
      error_message: error
    )
    shelf.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg"), "rb"),
      filename: "shelf.jpg",
      content_type: "image/jpeg"
    )
    shelf.save!
    shelf
  end

  def payload_with(entries, below: [])
    {"books" => entries + below, "unidentified" => []}
  end
end
