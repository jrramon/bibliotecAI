require "test_helper"

class BookTest < ActiveSupport::TestCase
  test ".normalize collapses case, punctuation, and diacritics" do
    assert_equal "episodios nacionales primera serie", Book.normalize("Episodios Nacionales (Primera serie)")
    assert_equal "linea de fuego", Book.normalize("Línea de Fuego")
    assert_equal "becoming a minha historia", Book.normalize("Becoming — A Minha História")
    assert_equal "1984", Book.normalize("1984")
  end

  test ".normalize treats equivalent variants as equal" do
    assert_equal Book.normalize("El Asedio"), Book.normalize("el asedio")
    assert_equal Book.normalize("Un día de cólera"), Book.normalize("Un día de cólera ")
    assert_equal Book.normalize("Episodios Nacionales (Primera serie)"),
      Book.normalize("Episodios nacionales, Primera serie")
  end

  test "genres are trimmed and deduplicated on assignment" do
    lib = create(:library)
    book = lib.books.create!(added_by_user: lib.owner, title: "Test",
      genres: [" Novela histórica ", "Novela histórica", "Guerra Civil "])
    assert_equal ["Novela histórica", "Guerra Civil"], book.genres
  end

  test "genres accept a comma-separated single element" do
    lib = create(:library)
    book = lib.books.create!(added_by_user: lib.owner, title: "Test",
      genres: ["Ensayo, Psicología, Ensayo"])
    assert_equal ["Ensayo", "Psicología"], book.genres
  end

  test "cdu and genres persist" do
    lib = create(:library)
    book = lib.books.create!(added_by_user: lib.owner, title: "X", cdu: "82-31", genres: ["Novela"])
    assert_equal "82-31", book.reload.cdu
    assert_equal ["Novela"], book.genres
  end

  test ".ordered_by('title') sorts case-insensitively by title" do
    lib = create(:library)
    create(:book, library: lib, added_by_user: lib.owner, title: "beta")
    create(:book, library: lib, added_by_user: lib.owner, title: "Alfa")
    create(:book, library: lib, added_by_user: lib.owner, title: "gamma")
    assert_equal %w[Alfa beta gamma], lib.books.ordered_by("title").pluck(:title)
  end

  test ".ordered_by('author') sorts case-insensitively, nulls/blanks last" do
    lib = create(:library)
    create(:book, library: lib, added_by_user: lib.owner, title: "B1", author: "borges, j.l.")
    create(:book, library: lib, added_by_user: lib.owner, title: "B2", author: "Atwood, M.")
    create(:book, library: lib, added_by_user: lib.owner, title: "B3", author: "")
    create(:book, library: lib, added_by_user: lib.owner, title: "B4", author: nil)
    titles = lib.books.ordered_by("author").pluck(:title)
    assert_equal "B2", titles[0], "Atwood should be first"
    assert_equal "B1", titles[1], "Borges should be second"
    assert_equal %w[B3 B4].sort, titles.last(2).sort, "Blank/null authors should land at the end"
  end

  test ".ordered_by('recent') falls back to created_at desc" do
    lib = create(:library)
    older = create(:book, library: lib, added_by_user: lib.owner, title: "Older", created_at: 2.days.ago)
    newer = create(:book, library: lib, added_by_user: lib.owner, title: "Newer", created_at: 1.hour.ago)
    assert_equal [newer.id, older.id], lib.books.ordered_by("recent").pluck(:id)
  end

  test ".ordered_by(unknown) defaults to recent" do
    lib = create(:library)
    older = create(:book, library: lib, added_by_user: lib.owner, title: "Older", created_at: 2.days.ago)
    newer = create(:book, library: lib, added_by_user: lib.owner, title: "Newer", created_at: 1.hour.ago)
    assert_equal [newer.id, older.id], lib.books.ordered_by("not-a-real-key").pluck(:id)
    assert_equal [newer.id, older.id], lib.books.ordered_by(nil).pluck(:id)
  end
end
