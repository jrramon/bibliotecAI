require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "user registers, gets signed in, and can sign out" do
    visit root_path

    click_on "Registrarse"

    fill_in "user_email", with: "nueva@bibliotecai.test"
    fill_in "user_password", with: "supersecret123"
    fill_in "user_password_confirmation", with: "supersecret123"
    click_on "Sign up"

    assert_selector "header.header", text: "nueva@bibliotecai.test"
    assert_selector "h1", text: "Mis bibliotecas"

    click_on "Cerrar sesión"

    assert_selector ".header-actions a", text: "Iniciar sesión"
    assert_selector ".header-actions a", text: "Registrarse"
  end

  test "existing user can sign in" do
    user = create(:user, email: "existente@bibliotecai.test", password: "supersecret123")

    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "supersecret123"
    click_on "Log in"

    assert_selector "header.header", text: user.email
  end
end
