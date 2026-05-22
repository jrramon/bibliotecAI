require "test_helper"

class CoverIdentificationJobTest < ActiveJob::TestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
  end

  test "aborts and marks failed when ClaudeBudget is exceeded" do
    cover = create(:cover_photo, library: @library, uploaded_by_user: @user, telegram_chat_id: nil)
    ClaudeBudget.stubs(:exceeded?).returns(true)
    ClaudeCoverIdentifier.expects(:call).never

    CoverIdentificationJob.new.perform(cover.id)

    assert_equal "failed", cover.reload.status
    assert_equal ClaudeBudget::EXHAUSTED_MESSAGE, cover.error_message
  end

  test "a completed cover with an identified title routes to the new-book form" do
    cover = create(:cover_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_raw_response: {"title" => "Kokoro"})

    assert_equal "books/new_form", CoverIdentificationJob.new.send(:partial_for, cover)
  end

  test "a completed cover with no identified title routes to the manual fallback" do
    cover = create(:cover_photo, library: @library, uploaded_by_user: @user,
      status: :completed, claude_raw_response: {"title" => "", "confidence" => 0})

    assert_equal "cover_photos/identification_failed", CoverIdentificationJob.new.send(:partial_for, cover)
  end
end
