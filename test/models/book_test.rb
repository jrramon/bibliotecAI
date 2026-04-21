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
end
