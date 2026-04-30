require "test_helper"

class Mcp::Tools::AddToWishlistTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
  end

  test "happy path: creates the item and returns ok with id" do
    result = nil
    assert_difference -> { @user.wishlist_items.count }, 1 do
      result = Mcp::Tools::AddToWishlist.call(user: @user, arguments: {
        "title" => "Kokoro", "author" => "Sōseki"
      })
    end

    assert result[:ok]
    refute result[:deduped]
    assert_kind_of Integer, result[:item_id]
    assert_equal "Kokoro", result[:title]
  end

  test "dedupes by title + author: second add returns the existing id with deduped=true" do
    first = Mcp::Tools::AddToWishlist.call(user: @user, arguments: {
      "title" => "Kokoro", "author" => "Sōseki"
    })

    assert_no_difference -> { @user.wishlist_items.count } do
      result = Mcp::Tools::AddToWishlist.call(user: @user, arguments: {
        "title" => "Kokoro", "author" => "Sōseki"
      })
      assert result[:ok]
      assert result[:deduped]
      assert_equal first[:item_id], result[:item_id]
    end
  end

  test "dedupes by ISBN even when title/author differ slightly" do
    @user.wishlist_items.create!(title: "Sanshirō", author: "Sōseki", isbn: "9781234567890")

    assert_no_difference -> { @user.wishlist_items.count } do
      result = Mcp::Tools::AddToWishlist.call(user: @user, arguments: {
        "title" => "Sanshiro: A Novel", "author" => "Natsume Sōseki",
        "isbn" => "9781234567890"
      })
      assert result[:deduped]
    end
  end

  test "missing title raises ArgumentError" do
    assert_raises(ArgumentError) do
      Mcp::Tools::AddToWishlist.call(user: @user, arguments: {})
    end
  end

  test "blank title raises ArgumentError" do
    assert_raises(ArgumentError) do
      Mcp::Tools::AddToWishlist.call(user: @user, arguments: {"title" => "  "})
    end
  end

  test "title too long surfaces as RecordInvalid (server returns isError)" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Mcp::Tools::AddToWishlist.call(user: @user, arguments: {
        "title" => "x" * 300
      })
    end
  end

  test "two users with the same title each get their own item (no cross-user dedupe)" do
    other = create(:user)
    other.wishlist_items.create!(title: "Kokoro", author: "Sōseki")

    assert_difference -> { @user.wishlist_items.count }, 1 do
      result = Mcp::Tools::AddToWishlist.call(user: @user, arguments: {
        "title" => "Kokoro", "author" => "Sōseki"
      })
      refute result[:deduped]
    end
  end

  test "stores optional note when given" do
    result = Mcp::Tools::AddToWishlist.call(user: @user, arguments: {
      "title" => "Kokoro", "note" => "leerlo este verano"
    })
    assert_equal "leerlo este verano", WishlistItem.find(result[:item_id]).note
  end
end
