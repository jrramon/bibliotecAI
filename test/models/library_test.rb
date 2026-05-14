require "test_helper"

class LibraryTest < ActiveSupport::TestCase
  test "#book_genres_with_counts returns [name, count] sorted by popularity then name" do
    lib = create(:library)
    create(:book, library: lib, added_by_user: lib.owner, title: "A", genres: ["Novela", "Ensayo"])
    create(:book, library: lib, added_by_user: lib.owner, title: "B", genres: ["Novela"])
    create(:book, library: lib, added_by_user: lib.owner, title: "C", genres: ["Novela", "Poesía"])
    create(:book, library: lib, added_by_user: lib.owner, title: "D", genres: ["Ensayo"])

    assert_equal [["Novela", 3], ["Ensayo", 2], ["Poesía", 1]],
      lib.book_genres_with_counts
  end

  test "#book_genres_with_counts ignores books without genres" do
    lib = create(:library)
    create(:book, library: lib, added_by_user: lib.owner, title: "X", genres: [])
    create(:book, library: lib, added_by_user: lib.owner, title: "Y", genres: ["Novela"])

    assert_equal [["Novela", 1]], lib.book_genres_with_counts
  end

  test "#book_genres_with_counts is empty for a library without books" do
    lib = create(:library)
    assert_equal [], lib.book_genres_with_counts
  end

  test "#book_genres_with_counts breaks ties alphabetically (case-insensitive)" do
    lib = create(:library)
    create(:book, library: lib, added_by_user: lib.owner, title: "A", genres: ["zombi"])
    create(:book, library: lib, added_by_user: lib.owner, title: "B", genres: ["Aventura"])
    create(:book, library: lib, added_by_user: lib.owner, title: "C", genres: ["mística"])

    names = lib.book_genres_with_counts.map(&:first)
    assert_equal %w[Aventura mística zombi], names
  end
end
