require "test_helper"

class Mcp::Tools::RemoveFromWishlistTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
  end

  test "happy path: deletes one of the user's items" do
    item = create(:wishlist_item, user: @user, title: "Kokoro")

    assert_difference -> { @user.wishlist_items.count }, -1 do
      result = Mcp::Tools::RemoveFromWishlist.call(user: @user, arguments: {"item_id" => item.id})
      assert result[:ok]
      assert_equal item.id, result[:item_id]
      assert_equal "Kokoro", result[:title]
    end

    refute WishlistItem.exists?(item.id)
  end

  test "non-existent id returns ok=false, not found" do
    result = Mcp::Tools::RemoveFromWishlist.call(user: @user, arguments: {"item_id" => 999_999})
    refute result[:ok]
    assert_equal "not found", result[:error]
  end

  test "id belonging to another user returns ok=false, not found (and does NOT delete)" do
    other = create(:user)
    foreign = create(:wishlist_item, user: other, title: "Ajeno")

    assert_no_difference -> { WishlistItem.count } do
      result = Mcp::Tools::RemoveFromWishlist.call(user: @user, arguments: {"item_id" => foreign.id})
      refute result[:ok]
      assert_equal "not found", result[:error]
    end

    assert WishlistItem.exists?(foreign.id), "the foreign user's item must still be there"
  end

  test "missing item_id raises ArgumentError" do
    assert_raises(ArgumentError) do
      Mcp::Tools::RemoveFromWishlist.call(user: @user, arguments: {})
    end
  end

  test "negative or zero item_id raises ArgumentError" do
    assert_raises(ArgumentError) do
      Mcp::Tools::RemoveFromWishlist.call(user: @user, arguments: {"item_id" => 0})
    end
    assert_raises(ArgumentError) do
      Mcp::Tools::RemoveFromWishlist.call(user: @user, arguments: {"item_id" => -1})
    end
  end
end
