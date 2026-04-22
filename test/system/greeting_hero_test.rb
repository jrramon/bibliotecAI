require "application_system_test_case"

class GreetingHeroTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice, name: "Mi casa")
    @library.memberships.create!(user: @bob, role: :member)
  end

  test "greets the viewer with the local part of their email" do
    sign_in_as(@alice)
    visit libraries_path
    assert_selector ".greeting-title", text: /(buenos d[ií]as|buenas tardes|buenas noches), alice/i
  end

  test "shows a pull-quote with attribution" do
    create(:book, library: @library, added_by_user: @alice,
      title: "El elogio de la sombra", author: "Junichirō Tanizaki",
      synopsis: "El secreto de la belleza está en la sombra. Un ensayo imprescindible sobre la estética japonesa.")

    sign_in_as(@alice)
    visit libraries_path

    assert_selector ".pull-quote blockquote"
    assert_selector ".quote-attribution", text: /TANIZAKI|SŌSEKI|KAWABATA|YOSANO|MURAKAMI/
  end

  test "shows new-activity count when others have added books since last visit" do
    # Alice's prior visit is 2 hours ago; Bob added a book since then.
    @alice.update!(last_seen_at: 2.hours.ago)
    create(:book, library: @library, added_by_user: @bob, title: "New arrival", created_at: 30.minutes.ago)

    sign_in_as(@alice)
    visit libraries_path

    assert_selector ".greeting-delta", text: /1 novedad/i
  end

  test "shows the quiet line when nothing new since the last visit" do
    @alice.update!(last_seen_at: 2.hours.ago)
    # No new activity by others.

    sign_in_as(@alice)
    visit libraries_path

    assert_selector ".greeting-delta--quiet"
  end

  test "touches last_seen_at on the first dashboard visit of the window" do
    assert_nil @alice.reload.last_seen_at
    sign_in_as(@alice)
    visit libraries_path
    assert_not_nil @alice.reload.last_seen_at
  end
end
