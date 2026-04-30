# Web side of the Telegram linking flow. The user, signed in on the
# webapp, hits POST /telegram/link → we mint a signed deep-link token
# and stash it in the flash so the next render of /users/edit can show
# the Telegram URL. They click that URL → Telegram opens the bot with
# `/start <token>` → Telegram::WebhooksController calls Telegram::Linker
# → bot replies «✅ vinculada».
class TelegramLinksController < ApplicationController
  before_action :authenticate_user!

  TOKEN_TTL = 1.day

  def create
    token = Rails.application.message_verifier(:telegram_link)
      .generate({user_id: current_user.id}, expires_in: TOKEN_TTL)

    redirect_to edit_user_registration_path,
      notice: "Pulsa el enlace para abrir Telegram y vincular tu cuenta.",
      flash: {
        telegram_deep_link: deep_link_for(token),
        telegram_start_command: "/start #{token}"
      }
  end

  def destroy
    current_user.unlink_telegram!
    redirect_to edit_user_registration_path, notice: "Telegram desvinculado."
  end

  private

  def deep_link_for(token)
    Telegram::Config.deep_link(token) || "(falta TELEGRAM_BOT_USERNAME en el entorno)"
  end
end
