require "application_system_test_case"

class LibrarySharingTest < ApplicationSystemTestCase
  include ActionMailer::TestHelper

  test "owner invites a new reader, invitee registers via link and joins" do
    owner = create(:user, email: "owner@bibliotecai.test", password: "supersecret123")
    sign_in_as(owner)

    click_on "Nueva biblioteca"
    fill_in "Nombre", with: "Familia"
    fill_in "Descripción", with: "Libros compartidos en casa."
    click_on "Crear biblioteca"

    assert_selector "h1", text: "Familia"

    click_on "Configuración"

    fill_in "invitation_email", with: "friend@bibliotecai.test"
    click_on "Enviar invitación"

    assert_text "Invitación enviada a friend@bibliotecai.test"
    perform_enqueued_jobs

    delivered = ActionMailer::Base.deliveries.last
    assert_equal ["friend@bibliotecai.test"], delivered.to
    token = Invitation.last.token
    accept_url = "/invitations/#{token}"

    click_on "Cerrar sesión"
    assert_selector ".header-actions a", text: "Iniciar sesión"

    # Invitee follows the link — not signed in yet → redirected to sign-up with email prefilled
    visit accept_url
    assert_current_path(/users\/sign_up/)
    assert_equal "friend@bibliotecai.test", find("#user_email").value

    fill_in "user_password", with: "anothersecret123"
    fill_in "user_password_confirmation", with: "anothersecret123"
    click_on "Sign up"

    # Devise restores the stored location after sign up → invitation auto-accepts.
    assert_selector "header.header", text: "friend"
    assert_selector "h1", text: "Familia"
    assert_text "Te has unido a «Familia»"

    visit libraries_path
    assert_selector ".library-card", text: "Familia"
  end

  test "second library member sees the library in their dashboard" do
    owner = create(:user)
    library = create(:library, name: "Club de lectura", owner: owner)
    invitee = create(:user, email: "new@bibliotecai.test", password: "supersecret123")
    invitation = library.invitations.create!(invited_by: owner, email: invitee.email)

    sign_in_as(invitee)
    visit invitation_path(token: invitation.token)

    assert_text "Te has unido a «Club de lectura»"
    visit libraries_path
    assert_selector ".library-card", text: "Club de lectura"
  end
end
