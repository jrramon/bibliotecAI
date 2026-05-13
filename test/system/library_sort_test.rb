require "application_system_test_case"

class LibrarySortTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user)
    @library = create(:library, owner: @alice)
    @zebra = create(:book, library: @library, added_by_user: @alice,
      title: "Zebra encuentra el norte", author: "Carmen Vidal", created_at: 3.days.ago)
    @alfa = create(:book, library: @library, added_by_user: @alice,
      title: "Alfa y el mar", author: "Bruno Aznar", created_at: 2.days.ago)
    @manga = create(:book, library: @library, added_by_user: @alice,
      title: "Manga curioso", author: "Akira Sato", created_at: 1.hour.ago)
    fast_sign_in(@alice)
  end

  test "default order is most recently added" do
    visit library_path(@library)

    first_card = first(".book-grid .book-card")
    assert_match(/Manga curioso/i, first_card.text)
  end

  test "changing sort to title reorders the grid and updates the URL" do
    visit library_path(@library)

    select "Título A–Z", from: "sort"

    assert_current_path(/sort=title/)
    first_card = first(".book-grid .book-card", wait: 5)
    assert_match(/Alfa y el mar/i, first_card.text)
  end

  test "changing sort to author orders by author A–Z" do
    visit library_path(@library)

    select "Autor A–Z", from: "sort"

    assert_current_path(/sort=author/)
    first_card = first(".book-grid .book-card", wait: 5)
    assert_match(/Manga curioso/i, first_card.text, "Akira Sato should sort first by author")
  end

  test "sort is preserved when combined with a search query" do
    visit library_path(@library, sort: "title")

    find(".book-search input[type=search]").set("a").send_keys(:return)

    assert_current_path(/sort=title/)
    assert_current_path(/q=a/)
    # Title-sorted, filtered: "Alfa y el mar" (starts with A) comes before "Manga curioso" and "Zebra…"
    first_card = first(".book-grid .book-card", wait: 5)
    assert_match(/Alfa y el mar/i, first_card.text)
  end
end
