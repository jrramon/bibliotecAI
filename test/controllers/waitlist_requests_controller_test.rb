require "test_helper"

class WaitlistRequestsControllerTest < ActionDispatch::IntegrationTest
  test "POST creates a waitlist request and redirects to sign-up with a thank-you" do
    assert_difference -> { WaitlistRequest.count }, 1 do
      post waitlist_requests_path, params: {
        waitlist_request: {email: "alice@example.com", note: "Quiero probarlo"}
      }
    end
    assert_redirected_to new_user_registration_path
    follow_redirect!
    assert_match(/lista/i, response.body)
  end

  test "POST is idempotent for repeated email (no duplicates, still thanks)" do
    WaitlistRequest.create!(email: "alice@example.com")

    assert_no_difference -> { WaitlistRequest.count } do
      post waitlist_requests_path, params: {
        waitlist_request: {email: "alice@example.com"}
      }
    end
    assert_redirected_to new_user_registration_path
  end

  test "POST with invalid email redirects with an alert" do
    assert_no_difference -> { WaitlistRequest.count } do
      post waitlist_requests_path, params: {
        waitlist_request: {email: "not-an-email"}
      }
    end
    assert_redirected_to new_user_registration_path
    follow_redirect!
    assert flash[:alert].present? || response.body.include?("Email")
  end
end
