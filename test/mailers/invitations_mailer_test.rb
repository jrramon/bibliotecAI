require "test_helper"

class InvitationsMailerTest < ActionMailer::TestCase
  test "invite renders a subject with the inviter and library, and a magic link" do
    invitation = create(:invitation, email: "to@example.test")
    mail = InvitationsMailer.invite(invitation)

    assert_equal ["to@example.test"], mail.to
    assert_match invitation.library.name, mail.subject
    assert_match invitation.invited_by.display_name, mail.subject
    assert_match invitation.token, mail.body.encoded
  end

  test "invite for an account invitation (no library) renders a magic link without mentioning a library" do
    invitation = create(:invitation, library: nil, email: "to@example.test")
    mail = InvitationsMailer.invite(invitation)

    assert_equal ["to@example.test"], mail.to
    assert_match invitation.invited_by.display_name, mail.subject
    assert_match "BibliotecAI", mail.subject
    assert_match invitation.token, mail.body.encoded
    assert_match "tu propia biblioteca", mail.body.encoded
  end
end
