require "test_helper"

class Eval::TrajectoryScorerTest < ActiveSupport::TestCase
  def call(tool, args = {}) = {tool: tool, arguments: args}

  def expect(name, args_include = nil)
    {"name" => name}.tap { |h| h["args_include"] = args_include if args_include }
  end

  test "exact single tool match scores 1.0" do
    r = Eval::TrajectoryScorer.call(actual: [call("list_my_libraries")], expected: [expect("list_my_libraries")])
    assert_equal 1.0, r[:score]
  end

  test "args match as case/accent-insensitive substrings" do
    r = Eval::TrajectoryScorer.call(
      actual: [call("search_books", {"query" => "Asimov", "limit" => 20})],
      expected: [expect("search_books", {"query" => "asimov"})]
    )
    assert_equal 1.0, r[:score]
  end

  test "accented author matches its transliteration" do
    r = Eval::TrajectoryScorer.call(
      actual: [call("add_to_wishlist", {"title" => "Kokoro", "author" => "Sōseki"})],
      expected: [expect("add_to_wishlist", {"title" => "kokoro", "author" => "soseki"})]
    )
    assert_equal 1.0, r[:score]
  end

  test "item_id matches exactly (integer)" do
    ok = Eval::TrajectoryScorer.call(
      actual: [call("remove_from_wishlist", {"item_id" => 9003})],
      expected: [expect("remove_from_wishlist", {"item_id" => 9003})]
    )
    assert_equal 1.0, ok[:score]

    wrong = Eval::TrajectoryScorer.call(
      actual: [call("remove_from_wishlist", {"item_id" => 1})],
      expected: [expect("remove_from_wishlist", {"item_id" => 9003})]
    )
    assert_equal 0.0, wrong[:score]
  end

  test "two-tool chain both matched scores 1.0 (order-independent)" do
    r = Eval::TrajectoryScorer.call(
      actual: [call("list_my_wishlist"), call("remove_from_wishlist", {"item_id" => 9003})],
      expected: [expect("list_my_wishlist"), expect("remove_from_wishlist", {"item_id" => 9003})]
    )
    assert_equal 1.0, r[:score]
  end

  test "extra/hallucinated call lowers precision" do
    r = Eval::TrajectoryScorer.call(
      actual: [call("list_my_libraries"), call("search_books", {"query" => "x"})],
      expected: [expect("list_my_libraries")]
    )
    assert_in_delta 0.5, r[:score], 1e-6 # recall 1.0 × precision 0.5
  end

  test "missed expected tool lowers recall" do
    r = Eval::TrajectoryScorer.call(actual: [], expected: [expect("list_my_libraries")])
    assert_equal 0.0, r[:score]
  end

  test "empty expected: no tool called scores 1.0" do
    r = Eval::TrajectoryScorer.call(actual: [], expected: [])
    assert_equal 1.0, r[:score]
  end

  test "empty expected: calling any tool scores 0.0" do
    r = Eval::TrajectoryScorer.call(actual: [call("list_my_libraries")], expected: [])
    assert_equal 0.0, r[:score]
  end
end
