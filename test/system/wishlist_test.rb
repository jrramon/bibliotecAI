require "application_system_test_case"

class WishlistTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice, name: "Mi casa")
  end

  test "wishlist page is empty by default and accessible from the sidebar" do
    fast_sign_in(@alice)
    visit libraries_path

    within(".sidebar") do
      click_on "Lista de deseos"
    end

    assert_selector "h1", text: /lista de deseos/i
    assert_text(/tu lista está vacía/i)
  end

  test "adding a wish manually appears in the list" do
    fast_sign_in(@alice)
    visit wishlist_path
    click_on "＋ Añadir deseo"

    within("dialog[open]") do
      fill_in "wishlist_item[title]", with: "Sanshiro"
      fill_in "wishlist_item[author]", with: "Natsume Soseki"
      fill_in "wishlist_item[note]", with: "para verano"
      click_on "Añadir a mi lista"
    end

    assert_selector ".wish-item h3", text: "Sanshiro"
    assert_selector ".wish-item-author", text: "NATSUME SOSEKI"
    assert_selector ".wish-note", text: /verano/
  end

  test "editing a wish removes and re-adds it visually" do
    create(:wishlist_item, user: @alice, title: "Old title")
    fast_sign_in(@alice)
    visit wishlist_path

    accept_confirm do
      find(".wish-item-delete").click
    end
    assert_text(/eliminado de tu lista/i)
    assert_no_selector ".wish-item h3", text: "Old title"
  end

  test "creating a book with matching title/author auto-prunes the wishlist item" do
    wish = create(:wishlist_item, user: @alice, title: "Sanshiro", author: "Natsume Soseki")
    assert_equal 1, @alice.wishlist_items.count

    # Book created by Alice in her library matching the wish → callback prunes it.
    @library.books.create!(title: "Sanshiro", author: "Natsume Soseki", added_by_user: @alice)

    assert_equal 0, @alice.wishlist_items.count
    assert_nil WishlistItem.find_by(id: wish.id)
  end

  test "auto-prune also matches by ISBN alone when titles differ slightly" do
    create(:wishlist_item, user: @alice, title: "Sanshiro: a novel", author: "Sōseki", isbn: "9781234567890")
    @library.books.create!(title: "Sanshirō", author: "Natsume Soseki", isbn: "9781234567890", added_by_user: @alice)

    assert_equal 0, @alice.wishlist_items.count
  end

  test "the wishlist is private per user — Bob does not see Alice's" do
    create(:wishlist_item, user: @alice, title: "Kokoro")

    fast_sign_in(@bob)
    visit wishlist_path

    assert_text(/tu lista está vacía/i)
    assert_no_text "Kokoro"
  end

  test "converting a wish opens the add-book form pre-filled, and creating the book prunes the wish" do
    create(:wishlist_item, user: @alice, title: "Sanshiro", author: "Natsume Soseki")

    fast_sign_in(@alice)
    visit wishlist_path

    within ".wish-item" do
      click_on "Tengo este libro →"
      click_on "Mi casa"
    end

    # Pre-filled new-book page:
    assert_field "book[title]", with: "Sanshiro"
    assert_field "book[author]", with: "Natsume Soseki"

    click_on "＋ Añadir a la estantería"
    assert_selector ".shelved-celebration", wait: 5

    assert_equal 0, @alice.wishlist_items.count
    assert @library.books.find_by(title: "Sanshiro").present?
  end
end
