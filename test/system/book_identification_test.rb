require "application_system_test_case"

class BookIdentificationTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    fast_sign_in(@user)
  end

  test "processing a shelf photo creates books from the Claude response" do
    fake_response = File.read(Rails.root.join("test/fixtures/files/claude_response.json"))
    parsed = JSON.parse(JSON.parse(fake_response).fetch("result"))
    fake_result = ClaudeBookIdentifier::Result.new(
      books: parsed["books"],
      unidentified: parsed["unidentified"],
      raw: parsed,
      image_width: parsed["image_width"],
      image_height: parsed["image_height"]
    )
    ClaudeBookIdentifier.stubs(:call).returns(fake_result)

    visit library_path(@library)
    click_on "＋ Subir foto de estantería"
    attach_file "shelf_photo_image", Rails.root.join("test/fixtures/files/shelf.jpg").to_s, make_visible: true
    click_on "Subir e identificar"

    assert_selector ".eyebrow", text: /foto de estantería/i

    photo = @library.shelf_photos.first
    # The host poller would pick this up; in tests we drive the job directly.
    BookIdentificationJob.new.perform(photo.id)

    assert_equal "completed", photo.reload.status
    assert_equal 2, @library.books.count
    titles = @library.books.pluck(:title)
    assert_includes titles, "Línea de fuego"
    assert_includes titles, "1984"
  end
end
