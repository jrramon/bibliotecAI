require "application_system_test_case"

class LibrarySearchTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice)
    @library.memberships.create!(user: @bob, role: :member)

    @agile = create(:book, library: @library, added_by_user: @alice,
      title: "Agile Software Development", author: "Alistair Cockburn",
      synopsis: "A comprehensive guide to agile methodologies and team dynamics.")
    @quiet = create(:book, library: @library, added_by_user: @alice,
      title: "Quiet", author: "Susan Cain",
      synopsis: "The power of introverts in a world that can't stop talking.")
    @plain = create(:book, library: @library, added_by_user: @alice,
      title: "Libro Muy Aburrido", author: "Nadie",
      synopsis: "Una historia sin nada interesante.")
  end

  test "matches on title" do
    sign_in_as(@alice)
    visit library_path(@library)

    find("input[type=search]").set("Quiet").send_keys(:return)

    assert_text "1 resultado para «Quiet»"
    assert_selector ".book-grid li", count: 1
    assert_selector ".book-grid li", text: "Quiet"
    assert_no_text "Agile Software Development"
  end

  test "matches on synopsis" do
    sign_in_as(@alice)
    visit library_path(@library, q: "introverts")

    assert_text "1 resultado"
    assert_selector ".book-grid li", text: "Quiet"
    assert_no_text "Agile"
  end

  test "matches on the searcher's own personal notes — not other users' notes" do
    @agile.user_book_notes.create!(user: @alice, body: "Nota secreta: serendipia leerlo")
    @quiet.user_book_notes.create!(user: @bob, body: "Anotación de Bob con la palabra serendipia")

    sign_in_as(@alice)
    visit library_path(@library, q: "serendipia")

    assert_text "1 resultado"
    # Alice should find her own note only — Bob's note shouldn't surface the book
    assert_selector ".book-grid li", text: "Agile Software Development"
    assert_no_text "Quiet"
  end

  test "empty search shows all books" do
    sign_in_as(@alice)
    visit library_path(@library)
    assert_selector ".book-grid li", count: 3
  end

  test "no matches renders the search-specific empty state" do
    sign_in_as(@alice)
    visit library_path(@library, q: "zzzzzz-no-match")

    assert_text "Sin resultados"
    assert_text "zzzzzz-no-match"
    assert_selector "a", text: "Ver todos los libros"
  end
end
