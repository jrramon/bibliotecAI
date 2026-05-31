class InvitationsMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @library = invitation.library
    @invited_by = invitation.invited_by
    @accept_url = invitation_url(token: invitation.token)

    subject =
      if @library
        "#{@invited_by.email} te invita a «#{@library.name}» en BibliotecAI"
      else
        "#{@invited_by.email} te invita a BibliotecAI"
      end

    mail(to: invitation.email, subject: subject)
  end
end
