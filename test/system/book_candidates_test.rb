require "application_system_test_case"

class BookCandidatesTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    @book = create(:book, library: @library, added_by_user: @user, title: "Typo Titlle", author: "Wrong Author")
    sign_in_as(@user)

    @fake_candidates = [
      BookCandidates::Candidate.new(
        volume_id: "vol1",
        title: "Proper Title",
        authors: ["Real Author"],
        publisher: "Penguin",
        published_date: "2020-03",
        description: "A short excerpt of the description goes here.",
        thumbnail_url: "",
        isbn_10: nil,
        isbn_13: "9780000000001",
        page_count: 320
      ),
      BookCandidates::Candidate.new(
        volume_id: "vol2",
        title: "Another Match",
        authors: ["Second Author"],
        publisher: "Anagrama",
        published_date: "2018",
        description: "",
        thumbnail_url: "",
        isbn_10: nil,
        isbn_13: "9780000000002",
        page_count: 200
      )
    ]
  end

  test "search renders candidates in the turbo frame" do
    BookCandidates.stubs(:call).returns(@fake_candidates)

    visit edit_library_book_path(@library, @book)
    assert_selector "h2", text: "Buscar en Google Books"

    # Input prefilled with current title + author
    assert_equal "Typo Titlle Wrong Author", find(".catalog-search-form input[name='q']").value

    click_on "Buscar candidatos"
    assert_selector ".candidate", count: 2
    assert_selector ".candidate h4", text: "Proper Title"
    assert_selector ".candidate .author", text: "Real Author"
    assert_selector ".candidate code", text: "9780000000001"
  end

  test "applying a candidate updates the book and redirects to the show page" do
    BookCandidates.stubs(:call).returns(@fake_candidates)

    visit edit_library_book_path(@library, @book)
    click_on "Buscar candidatos"

    within first(".candidate") do
      click_on "Aplicar este"
    end

    assert_text "Datos aplicados desde Google Books"
    assert_current_path(%r{/libraries/[^/]+/books/[^/]+\z})
    assert_selector "h1", text: "Proper Title"

    @book.reload
    assert_equal "Proper Title", @book.title
    assert_equal "Real Author", @book.author
    assert_equal "9780000000001", @book.isbn
  end

  test "empty result shows a helpful message" do
    BookCandidates.stubs(:call).returns([])

    visit edit_library_book_path(@library, @book)
    click_on "Buscar candidatos"

    assert_text "Sin resultados"
  end

  test "applying a candidate over a book with prior data asks to confirm and overwrites" do
    @book.update!(
      subtitle: "prior subtitle", publisher: "Prior", published_year: 1999,
      page_count: 123, language: "en", synopsis: "Lingering synopsis from earlier."
    )
    sparse = BookCandidates::Candidate.new(
      volume_id: "sparse",
      title: "Only Title Set",
      subtitle: nil,
      authors: ["Just Someone"],
      publisher: nil,
      published_date: nil,
      description: nil,
      thumbnail_url: "",
      isbn_10: nil,
      isbn_13: nil,
      page_count: nil,
      language: nil
    )
    BookCandidates.stubs(:call).returns([sparse])

    visit edit_library_book_path(@library, @book)
    click_on "Buscar candidatos"

    accept_confirm do
      within first(".candidate") { click_on "Aplicar este" }
    end

    assert_text "Datos aplicados desde Google Books"
    @book.reload
    assert_equal "Only Title Set", @book.title
    assert_equal "Just Someone", @book.author
    assert_nil @book.subtitle
    assert_nil @book.publisher
    assert_nil @book.published_year
    assert_nil @book.page_count
    assert_nil @book.synopsis
  end
end
