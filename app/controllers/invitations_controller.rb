class InvitationsController < ApplicationController
  before_action :authenticate_user!, except: %i[show]
  before_action :set_library, only: %i[create resend destroy]
  before_action :require_owner!, only: %i[create resend destroy]
  before_action :set_invitation, only: %i[resend destroy]

  def create
    @invitation = @library.invitations.build(invitation_params.merge(invited_by: current_user))
    if @invitation.save
      InvitationsMailer.invite(@invitation).deliver_later
      redirect_to settings_library_path(@library), notice: "Invitación enviada a #{@invitation.email}."
    else
      redirect_to settings_library_path(@library), alert: @invitation.errors.full_messages.to_sentence
    end
  end

  # Extends the expiry and re-sends the email. Only works on unaccepted
  # invitations — accepted ones are done, the member is already in.
  def resend
    if @invitation.accepted?
      redirect_to settings_library_path(@library), alert: "Esta invitación ya fue aceptada."
      return
    end

    @invitation.resend!
    InvitationsMailer.invite(@invitation).deliver_later
    redirect_to settings_library_path(@library),
      notice: "Invitación reenviada a #{@invitation.email} · expira #{l(@invitation.expires_at.to_date, format: :long)}."
  end

  def destroy
    email = @invitation.email
    @invitation.destroy
    redirect_to settings_library_path(@library), notice: "Invitación a #{email} cancelada."
  end

  def show
    @invitation = Invitation.find_by!(token: params[:token])

    if @invitation.expired? || @invitation.accepted?
      redirect_to root_path, alert: "Esta invitación ya no es válida."
      return
    end

    unless user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_registration_path(email: @invitation.email),
        notice: "Crea una cuenta con #{@invitation.email} para unirte a «#{@invitation.library.name}»."
      return
    end

    if @invitation.claimable_by?(current_user)
      @invitation.accept!(current_user)
      redirect_to @invitation.library, notice: "Te has unido a «#{@invitation.library.name}»."
    else
      redirect_to root_path, alert: "Esta invitación fue enviada a #{@invitation.email}. Inicia sesión con esa cuenta."
    end
  end

  private

  def set_library
    @library = current_user.libraries.friendly.find(params[:library_id])
  end

  def set_invitation
    @invitation = @library.invitations.find(params[:id])
  end

  def require_owner!
    membership = current_user.memberships.find_by(library: @library)
    return if membership&.owner?
    redirect_to @library, alert: "Solo el propietario puede invitar."
  end

  def invitation_params
    params.expect(invitation: [:email])
  end
end
