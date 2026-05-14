require "test_helper"

class BookIdentificationJobTest < ActiveJob::TestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
  end

  test "completed shelf with telegram_chat_id triggers NotifyIdentifiedShelf" do
    shelf = create(:shelf_photo, library: @library, uploaded_by_user: @user, telegram_chat_id: 4242)

    ClaudeBookIdentifier.expects(:call).returns(stub_result)
    ShelfImageAnnotator.expects(:call)
    Telegram::NotifyIdentifiedShelf.expects(:call).with do |arg|
      arg.id == shelf.id && arg.status == "completed"
    end

    BookIdentificationJob.new.perform(shelf.id)
  end

  test "completed shelf WITHOUT telegram_chat_id (web upload) does not notify" do
    shelf = create(:shelf_photo, library: @library, uploaded_by_user: @user, telegram_chat_id: nil)

    ClaudeBookIdentifier.expects(:call).returns(stub_result)
    ShelfImageAnnotator.expects(:call)
    Telegram::NotifyIdentifiedShelf.expects(:call).never

    BookIdentificationJob.new.perform(shelf.id)
  end

  test "failed shelf with telegram_chat_id still notifies, then re-raises" do
    shelf = create(:shelf_photo, library: @library, uploaded_by_user: @user, telegram_chat_id: 4242)

    ClaudeBookIdentifier.expects(:call).raises(ClaudeBookIdentifier::Error.new("boom"))
    Telegram::NotifyIdentifiedShelf.expects(:call).with do |arg|
      arg.id == shelf.id && arg.status == "failed"
    end

    assert_raises(ClaudeBookIdentifier::Error) do
      BookIdentificationJob.new.perform(shelf.id)
    end
  end

  test "a notifier crash never propagates out of the job" do
    shelf = create(:shelf_photo, library: @library, uploaded_by_user: @user, telegram_chat_id: 4242)

    ClaudeBookIdentifier.expects(:call).returns(stub_result)
    ShelfImageAnnotator.expects(:call)
    Telegram::NotifyIdentifiedShelf.expects(:call).raises(StandardError.new("downstream blew up"))

    assert_nothing_raised do
      BookIdentificationJob.new.perform(shelf.id)
    end
    assert_equal "completed", shelf.reload.status
  end

  private

  def stub_result
    Struct.new(:books, :unidentified, :image_width, :image_height, :raw, :usage)
      .new([], [], 1000, 1000, {"books" => [], "unidentified" => []}, nil)
  end
end
