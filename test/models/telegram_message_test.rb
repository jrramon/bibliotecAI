require "test_helper"

class TelegramMessageTest < ActiveSupport::TestCase
  test "creates with sane defaults" do
    msg = TelegramMessage.create!(chat_id: 1, update_id: 1, text: "hi")
    assert_predicate msg, :pending?
    assert_nil msg.user
  end

  test "rejects duplicate update_id" do
    TelegramMessage.create!(chat_id: 1, update_id: 42, text: "first")
    err = assert_raises(ActiveRecord::RecordInvalid) do
      TelegramMessage.create!(chat_id: 2, update_id: 42, text: "second")
    end
    assert_match(/update.*has already been taken/i, err.message)
  end

  test "recent scope orders by created_at desc" do
    older = TelegramMessage.create!(chat_id: 1, update_id: 1, text: "a", created_at: 2.minutes.ago)
    newer = TelegramMessage.create!(chat_id: 1, update_id: 2, text: "b")
    assert_equal [newer, older], TelegramMessage.recent.to_a
  end

  test "status enum exposes ?-predicates" do
    msg = TelegramMessage.create!(chat_id: 1, update_id: 99, text: "x", status: :completed)
    assert_predicate msg, :completed?
    refute_predicate msg, :pending?
  end
end
