require "test_helper"
require "stringio"

class ClaudeUsageReportTest < ActiveSupport::TestCase
  setup do
    @library = create(:library)
    @user = @library.owner
  end

  test "returns zeros when there are no completed invocations" do
    output = StringIO.new
    ClaudeUsageReport.new.run(format: "json", io: output)
    parsed = JSON.parse(output.string)

    assert_equal 4, parsed["windows"].size
    parsed["windows"].each do |window|
      assert_equal 0, window["totals"]["count_total"]
      assert_equal 0.0, window["totals"]["cost_total"]
    end
  end

  test "uses flat estimates for completed rows without claude_usage" do
    2.times do
      create(:shelf_photo, library: @library, uploaded_by_user: @user,
        status: :completed, claude_usage: nil)
    end

    week = report_window("últimos 7d")
    shelf = week["shelf"]

    assert_equal 2, shelf["count_total"]
    assert_equal 0, shelf["count_measured"]
    assert_equal 2, shelf["count_estimated"]
    assert_equal 0.0, shelf["cost_real"]
    assert_in_delta 2 * ClaudeUsageReport::SHELF_ESTIMATE_USD,
      shelf["cost_estimated"], 0.0001
  end

  test "sums real costs from claude_usage and estimates the rest" do
    create(:shelf_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: {"total_cost_usd" => 0.50})
    create(:shelf_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: {"total_cost_usd" => 0.25})
    create(:shelf_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: nil)

    shelf = report_window("últimos 7d")["shelf"]

    assert_equal 3, shelf["count_total"]
    assert_equal 2, shelf["count_measured"]
    assert_equal 1, shelf["count_estimated"]
    assert_in_delta 0.75, shelf["cost_real"], 0.0001
    assert_in_delta ClaudeUsageReport::SHELF_ESTIMATE_USD,
      shelf["cost_estimated"], 0.0001
    assert_in_delta 0.75 + ClaudeUsageReport::SHELF_ESTIMATE_USD,
      shelf["cost_total"], 0.0001
  end

  test "ignores rows that are not :completed" do
    create(:shelf_photo, library: @library, uploaded_by_user: @user, status: :pending)
    create(:shelf_photo, library: @library, uploaded_by_user: @user, status: :processing)
    create(:shelf_photo, library: @library, uploaded_by_user: @user, status: :failed,
      claude_usage: {"total_cost_usd" => 99.0})

    shelf = report_window("últimos 7d")["shelf"]

    assert_equal 0, shelf["count_total"]
    assert_equal 0.0, shelf["cost_real"]
  end

  test "filters by time window" do
    create(:shelf_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: {"total_cost_usd" => 1.0})
    old = create(:shelf_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: {"total_cost_usd" => 2.0})
    old.update_column(:created_at, 45.days.ago)

    parsed = run_report
    last_7d = parsed["windows"].find { |w| w["window"] == "últimos 7d" }
    last_30d = parsed["windows"].find { |w| w["window"] == "últimos 30d" }
    last_90d = parsed["windows"].find { |w| w["window"] == "últimos 90d" }

    assert_equal 1, last_7d["shelf"]["count_total"], "45d-old row must not enter 7d window"
    assert_equal 1, last_30d["shelf"]["count_total"], "45d-old row must not enter 30d window"
    assert_equal 2, last_90d["shelf"]["count_total"], "45d-old row must enter 90d window"
    assert_in_delta 1.0, last_30d["shelf"]["cost_real"], 0.0001
    assert_in_delta 3.0, last_90d["shelf"]["cost_real"], 0.0001
  end

  test "renders a human-readable table by default" do
    create(:shelf_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_usage: {"total_cost_usd" => 0.10})

    output = StringIO.new
    ClaudeUsageReport.new.run(format: "table", io: output)
    text = output.string

    assert_match(/Consumo de `claude -p`/, text)
    assert_match(/últimas 24h/, text)
    assert_match(/últimos 90d/, text)
    assert_match(/shelf/, text)
    assert_match(/TOTAL/, text)
  end

  private

  def run_report
    output = StringIO.new
    ClaudeUsageReport.new.run(format: "json", io: output)
    JSON.parse(output.string)
  end

  def report_window(label)
    run_report["windows"].find { |w| w["window"] == label }
  end
end
