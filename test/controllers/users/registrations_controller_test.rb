require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @library_owner = create(:user)
    @library = create(:library, owner: @library_owner)
  end

  test "GET /users/sign_up renders the waitlist page (no Devise default form)" do
    get new_user_registration_path
    assert_response :ok
    assert_match(/Lista de espera/i, response.body)
    assert_match(/Apuntarme a la lista/i, response.body)
  end

  test "POST /users blocks public registration when no invitation exists for the email" do
    assert_no_difference -> { User.count } do
      post user_registration_path, params: {
        user: {email: "stranger@example.com", password: "password123", password_confirmation: "password123", name: "Stranger"}
      }
    end
    assert_redirected_to new_user_registration_path
    follow_redirect!
    assert_match(/invitación/i, response.body)
  end

  test "POST /users allows registration when the email matches a pending invitation" do
    @library.invitations.create!(email: "invited@example.com", invited_by: @library_owner)

    assert_difference -> { User.count }, 1 do
      post user_registration_path, params: {
        user: {email: "invited@example.com", password: "password123", password_confirmation: "password123", name: "Invited"}
      }
    end
  end

  test "POST /users still blocks when the matching invitation is expired" do
    @library.invitations.create!(email: "late@example.com", invited_by: @library_owner, expires_at: 1.day.ago)

    assert_no_difference -> { User.count } do
      post user_registration_path, params: {
        user: {email: "late@example.com", password: "password123", password_confirmation: "password123", name: "Late"}
      }
    end
  end

  test "POST /users with an invalid password for an invited email re-renders the registration form with errors, not the waitlist" do
    @library.invitations.create!(email: "invited@example.com", invited_by: @library_owner)

    assert_no_difference -> { User.count } do
      post user_registration_path, params: {
        user: {email: "invited@example.com", password: "short", password_confirmation: "short", name: "Invited"}
      }
    end

    assert_response :unprocessable_entity
    assert_match(/Crea tu cuenta/i, response.body)           # invitee registration form
    assert_no_match(/Apuntarme a la lista/i, response.body)  # NOT the waitlist form
  end

  test "POST /users persists the name on an invited registration" do
    @library.invitations.create!(email: "named@example.com", invited_by: @library_owner)

    post user_registration_path, params: {
      user: {email: "named@example.com", password: "password123", password_confirmation: "password123", name: "Ada"}
    }

    assert_equal "Ada", User.find_by(email: "named@example.com").name
  end

  test "POST /users allows registration when an account invitation (no library) matches the email" do
    Invitation.create!(email: "indep@example.com", invited_by: @library_owner, library: nil)

    assert_difference -> { User.count }, 1 do
      post user_registration_path, params: {
        user: {email: "indep@example.com", password: "password123", password_confirmation: "password123", name: "Indie"}
      }
    end
  end
end
