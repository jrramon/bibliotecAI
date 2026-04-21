require "application_system_test_case"

class CoverPhotoIdentificationTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user, name: "Mi casa")
    sign_in_as(@user)
  end

  test "uploading a cover photo pre-fills the add-book form" do
    ClaudeCoverIdentifier.stubs(:call).returns(
      "title" => "Sanshiro",
      "author" => "Natsume Soseki",
      "publisher" => "Gredos",
      "published_year" => 1908,
      "language" => "es",
      "confidence" => 0.92
    )

    visit library_path(@library)
    click_on "＋ Añadir libro"

    within("dialog[open]") do
      find("[data-action~='cover-upload#pick']").click
      attach_file(
        "image",
        Rails.root.join("test/fixtures/files/shelf.jpg").to_s,
        make_visible: true
      )
    end

    assert_selector ".cover-analyzing", text: /analizando portada/i

    photo = @library.cover_photos.last
    assert_not_nil photo
    CoverIdentificationJob.new.perform(photo.id)

    # Job broadcasts the pre-filled form back into the modal via turbo_stream_from.
    assert_field "book[title]", with: "Sanshiro", wait: 5
    assert_field "book[author]", with: "Natsume Soseki"
    assert_selector ".cover-identified-hint", text: /identificados desde la portada/i
  end

  test "submitting the pre-filled form attaches the uploaded photo as the book cover" do
    ClaudeCoverIdentifier.stubs(:call).returns(
      "title" => "Sanshiro",
      "author" => "Natsume Soseki"
    )

    visit library_path(@library)
    click_on "＋ Añadir libro"
    within("dialog[open]") do
      find("[data-action~='cover-upload#pick']").click
      attach_file("image", Rails.root.join("test/fixtures/files/shelf.jpg").to_s,
        make_visible: true)
    end

    assert_selector ".cover-analyzing"
    photo = @library.cover_photos.last
    CoverIdentificationJob.new.perform(photo.id)

    assert_field "book[title]", with: "Sanshiro", wait: 5
    within("dialog[open]") do
      click_on "＋ Añadir a la estantería"
    end

    assert_selector ".shelved-celebration", wait: 5
    book = @library.books.find_by(title: "Sanshiro")
    assert_not_nil book
    assert book.cover_image.attached?, "expected the cover photo to be attached to the new book"
  end

  test "failed identification surfaces a clear error state" do
    ClaudeCoverIdentifier.stubs(:call).raises(ClaudeCoverIdentifier::Error, "boom")

    visit library_path(@library)
    click_on "＋ Añadir libro"
    within("dialog[open]") do
      find("[data-action~='cover-upload#pick']").click
      attach_file("image", Rails.root.join("test/fixtures/files/shelf.jpg").to_s,
        make_visible: true)
    end

    assert_selector ".cover-analyzing"
    photo = @library.cover_photos.last
    assert_not_nil photo
    assert_raises(ClaudeCoverIdentifier::Error) { CoverIdentificationJob.new.perform(photo.id) }

    assert_equal "failed", photo.reload.status
    assert_selector ".cover-analyzing--failed", text: /no pude leer la portada/i, wait: 5
  end
end
