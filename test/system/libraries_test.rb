require "application_system_test_case"

class LibrariesTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    sign_in_as(@user)
  end

  test "user creates a library and lands on its page" do
    visit libraries_path

    assert_selector "h1", text: "Mis bibliotecas"
    assert_text "Aún no tienes bibliotecas"

    click_on "Nueva biblioteca"
    fill_in "Nombre", with: "Mi casa"
    fill_in "Descripción", with: "Libros del salón."
    click_on "Crear biblioteca"

    assert_selector "h1", text: "Mi casa"
    assert_text @user.email
    assert_current_path(/\/libraries\/mi-casa/)
  end

  test "user only sees their own libraries in the dashboard" do
    own = create(:library, name: "Propia", owner: @user)
    _other = create(:library, name: "Ajena")

    visit libraries_path

    assert_selector "li", text: "Propia"
    assert_no_text "Ajena"

    _ignored = own # keep rubocop/standard quiet about unused block-local
  end
end
