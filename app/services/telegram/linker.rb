module Telegram
  # Verifies the signed `/start <token>` deep-link payload and binds the
  # `chat_id` to the User the token points at.
  #
  # Token is generated from /users/edit by TelegramLinksController via
  # `Rails.application.message_verifier(:telegram_link).generate({user_id:},
  # expires_in: 1.day)` and pasted into `https://t.me/<bot>?start=<token>`.
  # Telegram delivers it as the argument of `/start <token>` in the very
  # first message.
  #
  # Returns a Result(:ok, :message). The webhook ships the `message` text
  # back to the user via Telegram::Client.send_message.
  class Linker
    Result = Struct.new(:ok, :message, keyword_init: true)

    INVALID = "Enlace de vinculación inválido o expirado. Genera uno nuevo desde tu perfil en BibliotecAI."
    OTHER_USER = "Este chat de Telegram ya está vinculado a otra cuenta. Desvincúlalo desde la otra cuenta primero."
    ALREADY_LINKED = "Esta cuenta ya estaba vinculada a este chat."
    LINKED = "✅ Cuenta vinculada. A partir de ahora hablamos directamente desde aquí."

    def self.call(token:, chat_id:, username: nil)
      new(token, chat_id, username).call
    end

    def initialize(token, chat_id, username)
      @token = token.to_s
      @chat_id = chat_id
      @username = username
    end

    def call
      return result(false, INVALID) if @token.blank?

      payload = verifier.verify(@token)
      user_id = payload.is_a?(Hash) ? (payload["user_id"] || payload[:user_id]) : nil
      user = User.find_by(id: user_id)
      return result(false, INVALID) unless user

      existing = User.find_by(telegram_chat_id: @chat_id)

      # chat_id is bound to a different user → refuse without leaking which.
      return result(false, OTHER_USER) if existing && existing.id != user.id

      # Already linked to this same user → idempotent. Refresh username in
      # case it changed in Telegram.
      if existing && existing.id == user.id
        if user.telegram_username != @username
          user.link_telegram!(chat_id: @chat_id, username: @username)
          broadcast_status(user)
        end
        return result(true, ALREADY_LINKED)
      end

      user.link_telegram!(chat_id: @chat_id, username: @username)
      broadcast_status(user)
      result(true, LINKED)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      result(false, INVALID)
    end

    private

    # If the user is sitting on /users/edit when the bind completes, the
    # turbo_stream_from there listens on [user, :telegram_status] and swaps
    # the partial in-place — no manual refresh.
    def broadcast_status(user)
      Turbo::StreamsChannel.broadcast_replace_to(
        [user, :telegram_status],
        target: ActionView::RecordIdentifier.dom_id(user, :telegram_status),
        partial: "users/registrations/telegram_section",
        locals: {user: user}
      )
    rescue => e
      Rails.logger.warn("Telegram::Linker broadcast failed: #{e.class}: #{e.message}")
    end

    def verifier
      Rails.application.message_verifier(:telegram_link)
    end

    def result(ok, message)
      Result.new(ok: ok, message: message)
    end
  end
end
