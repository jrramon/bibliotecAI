class InvitationsMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @library = invitation.library
    @invited_by = invitation.invited_by
    @accept_url = invitation_url(token: invitation.token)

    mail(
      to: invitation.email,
      subject: "#{@invited_by.email} te invita a «#{@library.name}» en BibliotecAI"
    )
  end
end
