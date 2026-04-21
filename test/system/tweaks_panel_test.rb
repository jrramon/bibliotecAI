require "application_system_test_case"

class TweaksPanelTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, owner: @user)
    sign_in_as(@user)
  end

  test "panel toggles open and applies palette to <html>" do
    visit libraries_path

    assert_selector ".tweaks-toggle"
    # Panel starts hidden
    assert_no_selector ".tweaks:not([hidden])"

    find(".tweaks-toggle").click
    assert_selector ".tweaks:not([hidden])"

    within(".tweaks") { click_on "Sumi" }

    assert_equal "dark", find("html")["data-theme"]
  end

  test "palette choice persists across reloads" do
    visit libraries_path

    find(".tweaks-toggle").click
    within(".tweaks") { click_on "Sepia" }
    assert_equal "sepia", find("html")["data-theme"]

    visit libraries_path
    # After reload, the inline <head> script should re-apply sepia before Stimulus wakes up.
    assert_equal "sepia", find("html")["data-theme"]
  end

  test "shelf layout choice is applied to <html> and persists" do
    visit libraries_path

    find(".tweaks-toggle").click
    within(".tweaks") { click_on "Lista" }

    assert_equal "list", find("html")["data-shelf-layout"]

    visit libraries_path
    assert_equal "list", find("html")["data-shelf-layout"]
  end

  test "guest users don't see the tweaks panel" do
    click_on "Cerrar sesión"
    assert_selector ".header-actions a", text: "Iniciar sesión"

    visit root_path
    assert_no_selector ".tweaks-toggle"
  end
end
