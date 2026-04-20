require "application_system_test_case"

class ShelfPhotoAnnotationTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    sign_in_as(@user)
  end

  test "annotated image is attached when Claude returns unidentified boxes" do
    fake_result = ClaudeBookIdentifier::Result.new(
      books: [{"title" => "Test", "author" => "Author", "confidence" => 0.9}],
      unidentified: [
        {"x1" => 50, "y1" => 40, "x2" => 150, "y2" => 240, "reason" => "blurred spine"},
        {"x1" => 200, "y1" => 50, "x2" => 260, "y2" => 260, "reason" => "cut off"}
      ],
      raw: {"books" => [], "unidentified" => []},
      image_width: 400,
      image_height: 300
    )
    ClaudeBookIdentifier.stubs(:call).returns(fake_result)

    assert_difference -> { @library.shelf_photos.count } do
      visit library_path(@library)
      click_on "＋ Subir foto de estantería"
      attach_file "shelf_photo_image", Rails.root.join("test/fixtures/files/shelf.jpg").to_s, make_visible: true
      click_on "Subir e identificar"
      assert_selector ".status-badge"
    end

    photo = @library.shelf_photos.first
    BookIdentificationJob.new.perform(photo.id)

    photo.reload
    assert_equal "completed", photo.status
    assert photo.annotated_image.attached?, "annotated_image should be attached when boxes present"

    visit library_shelf_photo_path(@library, photo)
    assert_selector "img[alt*='no identificados']"
  end

  test "annotated image is skipped when no unidentified boxes" do
    fake_result = ClaudeBookIdentifier::Result.new(
      books: [{"title" => "Solo", "author" => "X", "confidence" => 0.95}],
      unidentified: [],
      raw: {"books" => [], "unidentified" => []},
      image_width: 400,
      image_height: 300
    )
    ClaudeBookIdentifier.stubs(:call).returns(fake_result)

    assert_difference -> { @library.shelf_photos.count } do
      visit library_path(@library)
      click_on "＋ Subir foto de estantería"
      attach_file "shelf_photo_image", Rails.root.join("test/fixtures/files/shelf.jpg").to_s, make_visible: true
      click_on "Subir e identificar"
      assert_selector ".status-badge"
    end

    photo = @library.shelf_photos.first
    BookIdentificationJob.new.perform(photo.id)

    photo.reload
    assert_equal "completed", photo.status
    assert_not photo.annotated_image.attached?
  end
end
