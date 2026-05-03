require "test_helper"

# End-to-end checks that the throttles in
# config/initializers/rack_attack.rb actually trip. We let real
# requests hit the controllers so we exercise the middleware chain.
class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store.clear
  end

  test "sign_in: 6th attempt within a minute returns 429" do
    5.times do
      post "/users/sign_in", params: {user: {email: "alice@example.com", password: "wrong"}}
    end
    post "/users/sign_in", params: {user: {email: "alice@example.com", password: "wrong"}}

    assert_response :too_many_requests
    assert_match(/Demasiadas peticiones/i, response.body)
    assert response.headers["retry-after"].present?
  end

  test "sign_in: throttle is per email (different emails not cross-counted)" do
    5.times do
      post "/users/sign_in", params: {user: {email: "alice@example.com", password: "x"}}
    end
    post "/users/sign_in", params: {user: {email: "bob@example.com", password: "x"}}

    refute_equal 429, response.status
  end

  test "password reset: 4th request for the same email gets throttled" do
    3.times do
      post "/users/password", params: {user: {email: "alice@example.com"}}
    end
    post "/users/password", params: {user: {email: "alice@example.com"}}

    assert_response :too_many_requests
  end

  test "waitlist: 6th submission from the same IP gets throttled" do
    5.times do |i|
      post "/waitlist_requests", params: {waitlist_request: {email: "user#{i}@example.com"}}
    end
    post "/waitlist_requests", params: {waitlist_request: {email: "user6@example.com"}}

    assert_response :too_many_requests
  end

  test "mcp: 61st hit from the same IP within a minute returns 429" do
    60.times do
      post "/mcp", env: {"HTTP_AUTHORIZATION" => "Bearer wrong"}
    end
    post "/mcp", env: {"HTTP_AUTHORIZATION" => "Bearer wrong"}

    assert_response :too_many_requests
  end

  test "non-throttled endpoints stay open" do
    20.times { get "/" }
    assert_response :ok
  end
end
