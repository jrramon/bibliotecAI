# Receives the public sign-up form. Public registration is closed;
# anyone landing on /users/sign_up sees a waitlist form instead of a
# Devise sign-up form. We persist their email + an optional note and
# bounce back to the same page with a thank-you flash. Idempotent:
# resubmitting the same email re-uses the existing row.
class WaitlistRequestsController < ApplicationController
  skip_before_action :touch_last_seen!, raise: false

  THANK_YOU = "¡Gracias! Tienes un sitio en la lista. Te escribimos en cuanto haya hueco."

  def create
    email = params.dig(:waitlist_request, :email).to_s
    note = params.dig(:waitlist_request, :note).to_s

    request_record = WaitlistRequest.find_or_initialize_by(email: email.strip.downcase)
    request_record.note = note if note.present? && request_record.note.blank?

    if request_record.save
      redirect_to new_user_registration_path, notice: THANK_YOU
    else
      redirect_to new_user_registration_path,
        alert: request_record.errors.full_messages.to_sentence.presence || "No se pudo guardar tu solicitud."
    end
  end
end
