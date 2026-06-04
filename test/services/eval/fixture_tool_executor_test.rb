require "test_helper"

class Eval::FixtureToolExecutorTest < ActiveSupport::TestCase
  setup { @ex = Eval::FixtureToolExecutor.new }

  def parse(str) = JSON.parse(str)

  test "list_my_libraries returns the canned library and records the call" do
    out = parse(@ex.call("list_my_libraries", {}))
    assert_equal "En casa", out.first["name"]
    assert_equal [{tool: "list_my_libraries", arguments: {}}], @ex.trajectory
  end

  test "search_books filters the canned set by query (title/author)" do
    out = parse(@ex.call("search_books", {"query" => "asimov"}))
    assert out.size >= 4
    assert(out.all? { |b| b["author"] == "Isaac Asimov" })
    assert_equal({tool: "search_books", arguments: {"query" => "asimov"}}, @ex.trajectory.last)
  end

  test "search_books returns empty for a non-matching query" do
    assert_empty parse(@ex.call("search_books", {"query" => "frestuyhf"}))
  end

  test "search_books honors limit" do
    out = parse(@ex.call("search_books", {"query" => "a", "limit" => 2}))
    assert_equal 2, out.size
  end

  test "list_my_wishlist returns the canned wishlist with item_ids" do
    out = parse(@ex.call("list_my_wishlist", {}))
    assert_equal 3, out.size
    assert(out.all? { |i| i["item_id"].is_a?(Integer) })
  end

  test "add_to_wishlist dedupes against the canned wishlist" do
    fresh = parse(@ex.call("add_to_wishlist", {"title" => "Sapiens", "author" => "Harari"}))
    assert_equal false, fresh["deduped"]

    dup = parse(@ex.call("add_to_wishlist", {"title" => "Matrescencia"}))
    assert_equal true, dup["deduped"]
  end

  test "remove_from_wishlist returns ok for a known id and not found otherwise" do
    ok = parse(@ex.call("remove_from_wishlist", {"item_id" => 9001}))
    assert_equal true, ok["ok"]

    missing = parse(@ex.call("remove_from_wishlist", {"item_id" => 1}))
    assert_equal false, missing["ok"]
    assert_equal "not found", missing["error"]
  end

  test "photo tools return a processing ack without state" do
    cover = parse(@ex.call("process_book_cover_photo", {"intent" => "wishlist"}))
    assert cover["ok"]
    assert_equal "wishlist", cover["intent"]

    shelf = parse(@ex.call("process_shelf_photo", {}))
    assert shelf["ok"]
  end
end
