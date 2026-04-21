require "application_system_test_case"

class BookCoverLookupTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    @book = create(:book, library: @library, added_by_user: @user, title: "Quiet", author: "Susan Cain")
    sign_in_as(@user)
  end

  test "no cover → Buscar portada button present; clicking it flashes the result" do
    BookCoverFetcher.stubs(:call).returns(:google_books)

    visit library_book_path(@library, @book)
    assert_selector "button", text: "Buscar portada"

    click_on "Buscar portada"
    assert_text "Portada encontrada en Google Books"
  end

  test "no cover found → flash alert" do
    BookCoverFetcher.stubs(:call).returns(:none)

    visit library_book_path(@library, @book)
    click_on "Buscar portada"
    assert_text "No se encontró portada"
  end

  test "already has cover → no Buscar portada button" do
    @book.cover_image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg")),
      filename: "existing.jpg",
      content_type: "image/jpeg"
    )

    visit library_book_path(@library, @book)
    assert_no_selector "button", text: "Buscar portada"
    assert_selector "img.detail-cover-image"
  end
end
