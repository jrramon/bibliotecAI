require "application_system_test_case"

class GlobalSearchTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @stranger = create(:user, email: "stranger@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice, name: "Mi casa")
    @library.memberships.create!(user: @bob, role: :member)
    @book = create(:book, library: @library, added_by_user: @alice,
      title: "Sanshiro", author: "Natsume Soseki", synopsis: "Joven provinciano en Tokio")
    @other_library = create(:library, owner: @stranger, name: "Ajena")
    create(:book, library: @other_library, added_by_user: @stranger, title: "Private stuff")
  end

  test "typing in the header search finds a book in one of my libraries" do
    sign_in_as(@alice)
    visit libraries_path
    fill_in "q", with: "Sanshiro"
    assert_selector ".search-section-title", text: /libros/i, wait: 5
    assert_selector ".search-hit .hit-title", text: "Sanshiro"
  end

  test "the search does not surface books from libraries I don't belong to" do
    sign_in_as(@alice)
    visit libraries_path
    fill_in "q", with: "Private stuff"
    assert_text(/sin resultados/i, wait: 5)
  end

  test "the search finds members of my libraries" do
    sign_in_as(@alice)
    visit libraries_path
    fill_in "q", with: "bob@"
    assert_selector ".search-section-title", text: /miembros/i, wait: 5
    assert_selector ".search-hit .hit-title", text: "bob@bibliotecai.test"
  end

  test "the search finds my own personal notes, not other users' notes" do
    create(:user_book_note, user: @alice, book: @book, body: "Me recordó a la abuela de Kumamoto")
    create(:user_book_note, user: @bob, book: @book, body: "Bob leyó esto")

    sign_in_as(@alice)
    visit libraries_path
    fill_in "q", with: "kumamoto"
    assert_selector ".search-section-title", text: /mis notas/i, wait: 5
    assert_selector ".search-hit", text: /kumamoto/i

    fill_in "q", with: "Bob leyó"
    assert_text(/sin resultados/i, wait: 5)
  end

  test "sidebar tags rail shows the library's most used genres and filters by click" do
    create(:book, library: @library, added_by_user: @alice, title: "Foo", genres: ["Novela histórica", "Ensayo"])
    create(:book, library: @library, added_by_user: @alice, title: "Bar", genres: ["Novela histórica"])

    sign_in_as(@alice)
    visit library_path(@library)

    within(".tags-rail") do
      assert_selector ".tag-chip", text: /Novela histórica/
      click_on "Novela histórica"
    end

    assert_selector ".book-list, .book-grid, .shelf", wait: 5
    assert_current_path library_path(@library, genre: "Novela histórica")
  end
end
