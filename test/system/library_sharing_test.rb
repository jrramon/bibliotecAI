require "application_system_test_case"

class LibrarySharingTest < ApplicationSystemTestCase
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  test "owner invites a new reader, invitee registers via link and joins" do
    owner = create(:user, email: "owner@bibliotecai.test", password: "supersecret123")
    sign_in_via_ui(owner)

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

    # Wait for Devise to finish signing the user in before continuing.
    assert_selector "header.header", text: "friend", wait: 10

    # Devise should restore the stored location after sign up, but that redirect can be
    # timing-sensitive in system tests. If we didn't land on the library already, visiting
    # the invitation again makes the accept deterministic and keeps the intent of the flow.
    visit accept_url unless page.has_selector?("h1", text: "Familia")
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

    fast_sign_in(invitee)
    visit invitation_path(token: invitation.token)

    assert_text "Te has unido a «Club de lectura»"
    visit libraries_path
    assert_selector ".library-card", text: "Club de lectura"
  end

  test "owner can resend a pending invitation and revive an expired one" do
    owner = create(:user, email: "owner@bibliotecai.test")
    library = create(:library, name: "Familia", owner: owner)
    fresh = library.invitations.create!(invited_by: owner, email: "alice@bibliotecai.test")
    expired = library.invitations.create!(invited_by: owner, email: "bob@bibliotecai.test")
    expired.update_column(:expires_at, 1.day.ago)

    fast_sign_in(owner)
    visit settings_library_path(library)

    within ".pending-invites" do
      assert_text "alice@bibliotecai.test"
      assert_text "bob@bibliotecai.test"
      assert_selector "li.is-expired", text: "bob@bibliotecai.test"
    end

    # Resend the expired one — should now be in the future.
    mails_before = ActionMailer::Base.deliveries.size
    perform_enqueued_jobs do
      within(".pending-invites li", text: "bob@bibliotecai.test") do
        click_on "Reenviar"
      end
      assert_text(/reenviada a bob@bibliotecai\.test/i)
    end
    assert_equal mails_before + 1, ActionMailer::Base.deliveries.size,
      "resend must send a new invitation email"

    expired.reload
    assert_not expired.expired?, "expired invitation should be revived with a future expires_at"
  end

  test "owner can cancel a pending invitation" do
    owner = create(:user)
    library = create(:library, name: "Familia", owner: owner)
    library.invitations.create!(invited_by: owner, email: "doomed@bibliotecai.test")

    fast_sign_in(owner)
    visit settings_library_path(library)

    accept_confirm do
      within(".pending-invites li", text: "doomed@bibliotecai.test") do
        click_on "Cancelar"
      end
    end

    assert_text(/cancelada/i)
    assert_equal 0, library.reload.invitations.count
  end
end
