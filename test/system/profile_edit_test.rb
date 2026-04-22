require "application_system_test_case"

class ProfileEditTest < ApplicationSystemTestCase
  setup do
    @user = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    fast_sign_in(@user)
  end

  test "header has a link to the profile page" do
    visit libraries_path
    assert_selector "a.header-profile-link"
    find("a.header-profile-link").click
    assert_selector "h1", text: /mi\s*perfil/i
  end

  test "updating the name changes the greeting on the dashboard" do
    visit edit_user_registration_path
    fill_in "user[name]", with: "Alice Gómez"
    click_on "Guardar cambios"

    assert_text(/actualizado correctamente/i, wait: 5)
    visit libraries_path
    assert_selector ".greeting-title", text: /Alice Gómez/
  end

  test "uploading an avatar replaces the initials circle with an image" do
    visit edit_user_registration_path
    attach_file "user[avatar]", Rails.root.join("test/fixtures/files/shelf.jpg").to_s
    click_on "Guardar cambios"

    assert_text(/actualizado correctamente/i, wait: 5)
    visit libraries_path
    assert_selector "img.avatar--image"
  end

  test "changing the password requires the current password" do
    visit edit_user_registration_path
    fill_in "user[password]", with: "brandnew123"
    fill_in "user[password_confirmation]", with: "brandnew123"
    click_on "Guardar cambios"

    # Without current_password, Devise rejects the update.
    assert_selector ".form-errors", text: /actual|current/i

    fill_in "user[password]", with: "brandnew123"
    fill_in "user[password_confirmation]", with: "brandnew123"
    fill_in "user[current_password]", with: "supersecret123"
    click_on "Guardar cambios"

    assert_text(/actualizado correctamente/i, wait: 5)
  end

  test "non-credential fields update without requiring the current password" do
    visit edit_user_registration_path
    fill_in "user[name]", with: "Alice G."
    click_on "Guardar cambios"
    # Verify the update via the UI (the redirect lands back on the dashboard
    # which shows the display name in the header and the greeting).
    assert_selector ".greeting-title", text: /alice g\.?/i, wait: 5
    assert_selector ".header-profile-link", text: /alice g\.?/i
  end
end
