require "test_helper"

class Mcp::Tools::ListMyWishlistTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
  end

  test "returns the user's wishlist most-recent first" do
    travel_to(2.days.ago) { create(:wishlist_item, user: @user, title: "Old") }
    create(:wishlist_item, user: @user, title: "New")

    result = Mcp::Tools::ListMyWishlist.call(user: @user, arguments: {})

    assert_equal ["New", "Old"], result.map { |r| r[:title] }
  end

  test "returns empty array when wishlist is empty" do
    result = Mcp::Tools::ListMyWishlist.call(user: @user, arguments: {})
    assert_equal [], result
  end

  test "default limit is 20" do
    25.times { |i| create(:wishlist_item, user: @user, title: "x#{i}") }
    result = Mcp::Tools::ListMyWishlist.call(user: @user, arguments: {})
    assert_equal 20, result.size
  end

  test "explicit limit is honoured" do
    5.times { |i| create(:wishlist_item, user: @user, title: "x#{i}") }
    result = Mcp::Tools::ListMyWishlist.call(user: @user, arguments: {"limit" => 2})
    assert_equal 2, result.size
  end

  test "out-of-range limit is clamped to MAX" do
    55.times { |i| create(:wishlist_item, user: @user, title: "x#{i}") }
    result = Mcp::Tools::ListMyWishlist.call(user: @user, arguments: {"limit" => 9999})
    assert_equal Mcp::Tools::ListMyWishlist::MAX_LIMIT, result.size
  end

  test "does not leak other users' wishlists" do
    other = create(:user)
    create(:wishlist_item, user: other, title: "Ajeno")

    result = Mcp::Tools::ListMyWishlist.call(user: @user, arguments: {})
    assert_equal [], result
  end

  test "exposes title, author, isbn, note, item_id" do
    create(:wishlist_item, user: @user, title: "T", author: "A", isbn: "9781234567890", note: "leer ya")
    result = Mcp::Tools::ListMyWishlist.call(user: @user, arguments: {}).first

    assert_equal "T", result[:title]
    assert_equal "A", result[:author]
    assert_equal "9781234567890", result[:isbn]
    assert_equal "leer ya", result[:note]
    assert_kind_of Integer, result[:item_id]
  end
end
