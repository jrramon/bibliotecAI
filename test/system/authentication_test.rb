require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "guest visiting the sign-up surface lands on the waitlist (open registration is closed)" do
    visit root_path

    click_on "Lista de espera"

    assert_selector "h1.waitlist-title", text: "Estamos abriendo poco a poco"
    assert_selector "form.waitlist-form input[type=email]"
    # The Devise sign-up fields must NOT be present for random visitors —
    # only invitees with a pending Invitation see them.
    assert_no_selector "input#user_password"
  end

  test "existing user can sign in" do
    user = create(:user, email: "existente@bibliotecai.test", password: "supersecret123")

    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "supersecret123"
    click_on "Log in"

    assert_selector "header.header", text: user.display_name
  end
end
