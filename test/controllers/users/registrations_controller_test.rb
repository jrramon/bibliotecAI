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
end
