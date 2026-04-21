require "application_system_test_case"

class ShelfLayoutsTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user, name: "Mi casa")
    @book_a = create(:book, library: @library, added_by_user: @user, title: "Alfa", author: "First Author")
    @book_b = create(:book, library: @library, added_by_user: @user, title: "Beta", author: "Second Author")
    sign_in_as(@user)
  end

  test "all three layouts are in the DOM; CSS toggles which one is visible" do
    visit library_path(@library)

    # Spines wrapper
    assert_selector ".books-layout--spine .shelf .spine", count: 2, visible: :all
    # Grid wrapper (default visible)
    assert_selector ".books-layout--grid .book-grid .book-card", count: 2
    # List wrapper
    assert_selector ".books-layout--list .book-row", count: 2, visible: :all
  end

  test "switching layout from tweaks updates the html data attribute and surfaces spines" do
    visit library_path(@library)

    # Grid is default
    assert_selector ".books-layout--grid .book-card:first-child", visible: true

    find(".tweaks-toggle").click
    within(".tweaks") { click_on "Lomos" }

    assert_equal "spine", find("html")["data-shelf-layout"]
    # After reload the inline head script re-applies, and the spine layout is shown
    visit library_path(@library)
    assert_equal "spine", find("html")["data-shelf-layout"]
    assert_selector ".books-layout--spine .spine", minimum: 2
  end

  test "each spine has a deterministic palette slot class" do
    visit library_path(@library)
    @library.books.each do |book|
      assert_selector ".books-layout--spine .spine.spine-slot-#{book.spine_slot}", visible: :all
    end
  end
end
