require "test_helper"

class Mcp::Tools::SearchBooksTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user, name: "Casa")
  end

  test "happy path: matches by title within the user's libraries" do
    create(:book, library: @library, title: "Kafka en la orilla", author: "Haruki Murakami")
    create(:book, library: @library, title: "Tokio Blues", author: "Haruki Murakami")
    create(:book, library: @library, title: "El Quijote", author: "Cervantes")

    result = Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "Murakami"})

    assert_equal 2, result.size
    assert result.all? { |r| r[:author] == "Haruki Murakami" }
    assert result.first.key?(:book_id)
    assert_equal "Casa", result.first[:library]
  end

  test "matches author and synopsis" do
    create(:book, library: @library, title: "Atlas", synopsis: "novela del mar")

    result = Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "mar"})

    assert_equal 1, result.size
    assert_equal "Atlas", result.first[:title]
  end

  test "default limit is 5" do
    7.times { |i| create(:book, library: @library, title: "Cosas #{i}") }

    result = Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "Cosas"})
    assert_equal 5, result.size
  end

  test "explicit limit is honoured" do
    7.times { |i| create(:book, library: @library, title: "Cosas #{i}") }

    result = Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "Cosas", "limit" => 2})
    assert_equal 2, result.size
  end

  test "limit out of range is clamped to MAX, not rejected" do
    25.times { |i| create(:book, library: @library, title: "Cosa #{i}") }

    result = Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "Cosa", "limit" => 9999})
    assert_equal Mcp::Tools::SearchBooks::MAX_LIMIT, result.size
  end

  test "missing query raises ArgumentError (server surfaces as isError)" do
    assert_raises(ArgumentError) do
      Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "  "})
    end
  end

  test "does not leak books from other users' libraries" do
    other = create(:user)
    other_lib = create(:library, owner: other, name: "Ajena")
    create(:book, library: other_lib, title: "Murakami secreto", author: "Haruki")

    result = Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "Murakami"})
    assert_empty result
  end

  test "returns empty array when nothing matches" do
    result = Mcp::Tools::SearchBooks.call(user: @user, arguments: {"query" => "nada de nada"})
    assert_equal [], result
  end
end
