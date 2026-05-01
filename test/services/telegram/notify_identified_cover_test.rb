require "test_helper"

class Telegram::NotifyIdentifiedCoverTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user, name: "Casa")
    @chat_id = 1_111_111
  end

  test "high-confidence completed cover auto-creates a Book and replies with the title" do
    cover = build_cover(status: :completed, telegram_chat_id: @chat_id, payload: {
      "title" => "Kokoro", "author" => "Sōseki", "confidence" => 0.9
    })

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:chat_id] == @chat_id && kwargs[:text].include?("Kokoro") && kwargs[:text].include?("Casa")
    end

    assert_difference -> { Book.count }, 1 do
      Telegram::NotifyIdentifiedCover.call(cover)
    end

    book = Book.last
    assert_equal "Kokoro", book.title
    assert_equal @user.id, book.added_by_user_id
    assert_equal @library.id, book.library_id
  end

  test "low-confidence completed cover does NOT create a Book and explains" do
    cover = build_cover(status: :completed, telegram_chat_id: @chat_id, payload: {
      "title" => "Algo", "confidence" => 0.2
    })

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/seguridad/i)
    end

    assert_no_difference -> { Book.count } do
      Telegram::NotifyIdentifiedCover.call(cover)
    end
  end

  test "missing title is treated as low confidence even if score is high" do
    cover = build_cover(status: :completed, telegram_chat_id: @chat_id, payload: {
      "title" => "", "confidence" => 0.99
    })

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/seguridad/i)
    end

    assert_no_difference -> { Book.count } do
      Telegram::NotifyIdentifiedCover.call(cover)
    end
  end

  test "failed cover replies with the error message" do
    cover = build_cover(status: :failed, telegram_chat_id: @chat_id, payload: nil, error: "boom")

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/error/i)
    end

    Telegram::NotifyIdentifiedCover.call(cover)
  end

  test "wishlist intent: high-confidence cover creates a WishlistItem and replies" do
    cover = build_cover(status: :completed, telegram_chat_id: @chat_id, intent: :wishlist, payload: {
      "title" => "Kokoro", "author" => "Sōseki", "confidence" => 0.9
    })

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].include?("Kokoro") && kwargs[:text].match?(/wishlist/i)
    end

    assert_difference -> { WishlistItem.count }, 1 do
      assert_no_difference -> { Book.count } do
        Telegram::NotifyIdentifiedCover.call(cover)
      end
    end

    item = WishlistItem.last
    assert_equal "Kokoro", item.title
    assert_equal "Sōseki", item.author
    assert_equal @user.id, item.user_id
  end

  test "wishlist intent: dedupes against existing wishlist items" do
    @user.wishlist_items.create!(title: "Kokoro", author: "Sōseki")
    cover = build_cover(status: :completed, telegram_chat_id: @chat_id, intent: :wishlist, payload: {
      "title" => "Kokoro", "author" => "Sōseki", "confidence" => 0.9
    })

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/ya estaba apuntado/i)
    end

    assert_no_difference -> { WishlistItem.count } do
      Telegram::NotifyIdentifiedCover.call(cover)
    end
  end

  test "wishlist intent + low confidence still falls back to the generic 'no pude identificar' reply" do
    cover = build_cover(status: :completed, telegram_chat_id: @chat_id, intent: :wishlist, payload: {
      "title" => "Algo", "confidence" => 0.2
    })

    Telegram::Client.expects(:send_message).with do |kwargs|
      kwargs[:text].match?(/seguridad/i)
    end

    assert_no_difference -> { WishlistItem.count } do
      assert_no_difference -> { Book.count } do
        Telegram::NotifyIdentifiedCover.call(cover)
      end
    end
  end

  test "nothing happens when telegram_chat_id is missing (web upload)" do
    cover = build_cover(status: :completed, telegram_chat_id: nil, payload: {
      "title" => "X", "confidence" => 0.9
    })

    Telegram::Client.expects(:send_message).never

    assert_no_difference -> { Book.count } do
      Telegram::NotifyIdentifiedCover.call(cover)
    end
  end

  private

  def build_cover(status:, telegram_chat_id:, payload:, error: nil, intent: :library)
    cover = CoverPhoto.new(
      library: @library,
      uploaded_by_user: @user,
      telegram_chat_id: telegram_chat_id,
      status: status,
      intent: intent,
      claude_raw_response: payload,
      error_message: error
    )
    cover.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg"), "rb"),
      filename: "shelf.jpg",
      content_type: "image/jpeg"
    )
    cover.save!
    cover
  end
end
