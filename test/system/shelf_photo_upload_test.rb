require "application_system_test_case"

class ShelfPhotoUploadTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    sign_in_as(@user)
  end

  test "user uploads a shelf photo and lands on the pending status page" do
    visit library_path(@library)

    click_on "＋ Subir foto de estantería"

    attach_file "shelf_photo_image", Rails.root.join("test/fixtures/files/shelf.jpg").to_s, make_visible: true
    click_on "Subir e identificar"

    assert_selector ".eyebrow", text: /foto de estantería/i
    assert_selector ".status-badge", text: /En cola|Identificando/i

    assert_equal 1, @library.reload.shelf_photos.count
    photo = @library.shelf_photos.first
    assert photo.image.attached?
    assert_equal @user.id, photo.uploaded_by_user_id
    assert_equal "pending", photo.status
  end
end
