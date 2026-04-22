require "application_system_test_case"

class ShelfPhotoUploadTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    fast_sign_in(@user)
  end

  test "user uploads a shelf photo and lands on the pending status page" do
    visit library_path(@library)

    click_on "＋ Subir foto de estantería"

    attach_file "shelf_photo[images][]", Rails.root.join("test/fixtures/files/shelf.jpg").to_s, make_visible: true
    click_on "Subir e identificar"

    assert_selector ".eyebrow", text: /foto de estantería/i
    assert_selector ".status-badge", text: /En cola|Identificando/i

    assert_equal 1, @library.reload.shelf_photos.count
    photo = @library.shelf_photos.first
    assert photo.image.attached?
    assert_equal @user.id, photo.uploaded_by_user_id
    assert_equal "pending", photo.status
  end

  test "user uploads multiple shelf photos at once, all queued as pending" do
    visit new_library_shelf_photo_path(@library)

    # Two copies of the same fixture — enough to prove the loop creates
    # one ShelfPhoto per file.
    fixture = Rails.root.join("test/fixtures/files/shelf.jpg").to_s
    attach_file "shelf_photo[images][]", [fixture, fixture], make_visible: true
    click_on "Subir e identificar"

    assert_text(/fotos subidas/i)
    assert_equal 2, @library.reload.shelf_photos.count
    assert @library.shelf_photos.all? { |p| p.status == "pending" && p.image.attached? }
  end
end
