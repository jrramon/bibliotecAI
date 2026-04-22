require "application_system_test_case"

class PublicWishlistTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123", name: "Alice Gómez")
    create(:wishlist_item, user: @alice, title: "Kokoro", author: "Natsume Soseki", note: "regalo cumple")
  end

  test "wishlist is private by default — no token means no public URL" do
    assert_nil @alice.wishlist_share_token
  end

  test "owner enables sharing, gets a URL, and logged-out visitors see the list" do
    fast_sign_in(@alice)
    visit wishlist_path
    find(".wishlist-share-summary").click
    click_on "Generar link público"

    assert_selector ".share-url-input", wait: 5
    share_url = find(".share-url-input").value
    assert_match(%r{/w/[A-Za-z0-9_\-]{20,}}, share_url)

    # Logged-out visitor:
    Capybara.reset_sessions!
    visit share_url
    assert_selector "h1", text: /Alice Gómez/
    assert_text "Kokoro"
    assert_text(/natsume soseki/i)
    assert_text "regalo cumple"

    # Does NOT leak private info:
    assert_no_text "alice@bibliotecai.test"
    assert_no_selector ".sidebar"
  end

  test "rotating the token invalidates the old URL" do
    @alice.regenerate_wishlist_share_token!
    old_url = Rails.application.routes.url_helpers.public_wishlist_url(
      token: @alice.wishlist_share_token, host: Capybara.app_host || "http://web:3001"
    )

    fast_sign_in(@alice)
    visit wishlist_path
    find(".wishlist-share-summary").click
    accept_confirm { click_on "Generar link nuevo" }

    # The old URL no longer matches any user → 404-ish.
    Capybara.reset_sessions!
    visit old_url
    assert_no_selector "h1", text: /Alice Gómez/
  end

  test "disabling sharing makes the URL stop working" do
    @alice.regenerate_wishlist_share_token!
    token = @alice.wishlist_share_token

    fast_sign_in(@alice)
    visit wishlist_path
    find(".wishlist-share-summary").click
    click_on "Dejar de compartir"

    assert_text(/ya no es p[uú]blica/i, wait: 5)
    assert_nil @alice.reload.wishlist_share_token

    Capybara.reset_sessions!
    visit "/w/#{token}"
    assert_no_text "Kokoro"
  end

  test "visiting an unknown token does not reveal any list" do
    Capybara.reset_sessions!
    visit "/w/unknown-token-1234567890abcdef"
    assert_no_text "Kokoro"
    assert_no_text "Alice Gómez"
  end
end
