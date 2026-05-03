require "test_helper"

# With Devise's paranoid mode on, the password-reset response must be
# indistinguishable for an existing email vs an unknown one. Otherwise
# an attacker can enumerate registered users one by one.
class PasswordResetParanoidTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store.clear
    @existing = create(:user, email: "real@example.com")
  end

  test "password reset response is identical for existing and unknown emails" do
    post "/users/password", params: {user: {email: "real@example.com"}}
    existing_status = response.status
    existing_redirect = response.redirect_url
    existing_flash = flash[:notice]

    post "/users/password", params: {user: {email: "ghost@example.com"}}
    ghost_status = response.status
    ghost_redirect = response.redirect_url
    ghost_flash = flash[:notice]

    # The status code, redirect location and flash text must be the
    # same — together they're what an attacker observes from the
    # outside. Anything different is an enumeration oracle.
    assert_equal existing_status, ghost_status
    assert_equal existing_redirect, ghost_redirect
    assert_equal existing_flash, ghost_flash
    # Sanity: with paranoid mode the flash must read "if your email
    # exists in our database…" — not "not found / no encontrado".
    refute_match(/not found|no encontrado|no existe|inválido/i, ghost_flash.to_s)
  end

  test "the existing user actually receives a reset email" do
    ActionMailer::Base.deliveries.clear
    post "/users/password", params: {user: {email: "real@example.com"}}
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal ["real@example.com"], ActionMailer::Base.deliveries.last.to
  end

  test "an unknown email triggers no email send" do
    ActionMailer::Base.deliveries.clear
    post "/users/password", params: {user: {email: "ghost@example.com"}}
    assert_equal 0, ActionMailer::Base.deliveries.size
  end
end
