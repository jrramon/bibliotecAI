require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  test "is valid without a library (account invitation)" do
    invitation = build(:invitation, library: nil)
    assert invitation.valid?, invitation.errors.full_messages.to_sentence
  end

  test "accept! on a library invitation joins it as member" do
    invitation = create(:invitation)
    user = create(:user, email: invitation.email)

    landing = invitation.accept!(user)

    assert_equal invitation.library, landing
    assert_equal "member", user.memberships.find_by(library: landing).role
    assert_empty user.owned_libraries
    assert invitation.reload.accepted?
  end

  test "accept! on an account invitation provisions the user's own library as owner" do
    invitation = create(:invitation, library: nil)
    user = create(:user, email: invitation.email, name: "Ada Lovelace")

    landing = invitation.accept!(user)

    assert_equal [landing], user.owned_libraries.to_a
    assert_equal "Biblioteca de Ada Lovelace", landing.name
    assert_equal "owner", user.memberships.find_by(library: landing).role
    assert invitation.reload.accepted?
  end

  test "account invitation library name falls back to the email local part when name is blank" do
    invitation = create(:invitation, library: nil)
    user = create(:user, email: "grace@example.test", name: nil)

    landing = invitation.accept!(user)

    assert_equal "Biblioteca de grace", landing.name
  end
end
