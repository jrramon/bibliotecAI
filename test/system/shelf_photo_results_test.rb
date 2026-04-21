require "application_system_test_case"

class ShelfPhotoResultsTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    @photo = @library.shelf_photos.build(uploaded_by_user: @user, status: :completed)
    @photo.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg")),
      filename: "shelf.jpg",
      content_type: "image/jpeg"
    )
    @photo.claude_raw_response = {
      "image_width" => 400,
      "image_height" => 300,
      "books" => [
        {"title" => "Quiet", "author" => "Susan Cain", "confidence" => 0.95, "cdu" => "159.923", "genres" => ["Psicología", "Ensayo"]},
        {"title" => "Too Blurry", "author" => "", "confidence" => 0.3, "cdu" => "", "genres" => []}
      ],
      "unidentified" => [
        {"x1" => 10, "y1" => 20, "x2" => 50, "y2" => 240, "reason" => "spine rotated"}
      ]
    }
    @photo.save!
    # Also create a matching Book in the library so the link is rendered
    create(:book, library: @library, added_by_user: @user, title: "Quiet", author: "Susan Cain")
    sign_in_as(@user)
  end

  test "show page surfaces identified, rejected, and unidentified entries" do
    visit library_shelf_photo_path(@library, @photo)

    assert_selector "h2", text: "Resultado de la identificación"

    within ".results-grid" do
      # identified
      assert_selector "h3", text: "libros añadidos", normalize_ws: true
      assert_selector ".conf.conf-high", text: "95%"
      assert_selector ".chip.chip-cdu", text: "159.923", normalize_ws: true
      assert_selector ".chip.chip-genre", text: "Psicología"
      # below-threshold
      assert_selector "h3", text: "confianza baja · descartados", normalize_ws: true
      assert_selector ".conf.conf-low", text: "30%"
      assert_text "Too Blurry"
      # unidentified
      assert_selector "h3", text: "spines no leídos", normalize_ws: true
      assert_text "spine rotated"
      assert_text "(10, 20)"
    end

    # Raw JSON is tucked inside a details element and contains the payload
    assert_selector "details.raw-json"
    assert_selector "details.raw-json pre", text: /"Quiet"/, visible: :all
  end

  test "identified book with a matching library row links to it" do
    visit library_shelf_photo_path(@library, @photo)

    within ".results-grid" do
      assert_selector "a", text: "Quiet"
    end
    click_on "Quiet"
    assert_selector "h1", text: "Quiet"
  end
end
