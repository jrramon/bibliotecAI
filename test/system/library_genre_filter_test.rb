require "application_system_test_case"

class LibraryGenreFilterTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user)
    @library = create(:library, owner: @alice)
    @novel_a = create(:book, library: @library, added_by_user: @alice,
      title: "Niebla", author: "Unamuno", genres: ["Novela"])
    @novel_b = create(:book, library: @library, added_by_user: @alice,
      title: "Pedro Páramo", author: "Rulfo", genres: ["Novela"])
    @essay = create(:book, library: @library, added_by_user: @alice,
      title: "Anatomía de la melancolía", author: "Burton", genres: ["Ensayo"])
    fast_sign_in(@alice)
  end

  test "chips render for every distinct genre with counts and 'Todos' active by default" do
    visit library_path(@library)

    within(".genre-chips") do
      assert_selector ".chip.on", text: "Todos"
      assert_selector ".chip", text: /Novela.*\(2\)/m
      assert_selector ".chip", text: /Ensayo.*\(1\)/m
    end
  end

  test "clicking a genre chip filters the grid and updates the URL" do
    visit library_path(@library)

    within(".genre-chips") { click_on "Ensayo" }

    assert_current_path(/genre=Ensayo/)
    within(".genre-chips") { assert_selector ".chip.on", text: /Ensayo/m }
    assert_selector ".book-grid .book-card", count: 1
    assert_text "Anatomía de la melancolía"
    assert_no_text "Niebla"
  end

  test "clicking 'Todos' clears the active genre filter" do
    visit library_path(@library, genre: "Ensayo")
    assert_selector ".book-grid .book-card", count: 1

    within(".genre-chips") { click_on "Todos" }

    assert_current_path library_path(@library)
    assert_selector ".book-grid .book-card", count: 3
  end

  test "genre filter is preserved when sort changes" do
    visit library_path(@library, genre: "Novela")
    assert_selector ".book-grid .book-card", count: 2

    select "Título A–Z", from: "sort"

    assert_current_path(/genre=Novela/)
    assert_current_path(/sort=title/)
    first_card = first(".book-grid .book-card", wait: 5)
    assert_match(/Niebla/i, first_card.text)
  end
end
