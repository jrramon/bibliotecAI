require "test_helper"

class ClaudeBudgetTest < ActiveSupport::TestCase
  setup do
    Rails.cache.delete(ClaudeBudget::CACHE_KEY)
    @user = create(:user)
    @library = create(:library, owner: @user)
  end

  teardown do
    Rails.cache.delete(ClaudeBudget::CACHE_KEY)
  end

  test "exceeded? returns false when MONTHLY_CLAUDE_BUDGET is not set" do
    ClaudeBudget.stubs(:budget_usd).returns(nil)
    ClaudeBudget.expects(:rolling_cost_usd).never
    assert_not ClaudeBudget.exceeded?
  end

  test "exceeded? returns false when rolling cost is below the budget" do
    ClaudeBudget.stubs(:budget_usd).returns(50.0)
    ClaudeBudget.stubs(:rolling_cost_usd).returns(10.0)
    assert_not ClaudeBudget.exceeded?
  end

  test "exceeded? returns true when rolling cost meets or exceeds the budget" do
    ClaudeBudget.stubs(:budget_usd).returns(50.0)
    ClaudeBudget.stubs(:rolling_cost_usd).returns(50.0)
    assert ClaudeBudget.exceeded?
  end

  test "rolling_cost_usd sums real claude_usage and estimated rows together" do
    create(:cover_photo,
      library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: {"total_cost_usd" => 1.25})
    create(:cover_photo,
      library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: nil)

    expected = 1.25 + ClaudeUsageReport::COVER_ESTIMATE_USD
    assert_in_delta expected, ClaudeBudget.rolling_cost_usd, 0.0001
  end

  test "rolling_cost_usd ignores rows older than the window and non-completed ones" do
    travel_to 31.days.ago do
      create(:cover_photo,
        library: @library, uploaded_by_user: @user,
        status: :completed, claude_usage: {"total_cost_usd" => 99.0})
    end
    create(:cover_photo,
      library: @library, uploaded_by_user: @user,
      status: :pending, claude_usage: {"total_cost_usd" => 99.0})

    assert_in_delta 0.0, ClaudeBudget.rolling_cost_usd, 0.0001
  end
end
