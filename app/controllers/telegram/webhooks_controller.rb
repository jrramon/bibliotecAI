module Telegram
  # Receives `update` POSTs from Telegram. The path-secret check authenticates
  # the call cheaply: only Telegram (and us, when we set the webhook) knows
  # the URL. CSRF is skipped because the caller has no Rails session, and
  # `authenticate_user!` is not in scope (no Devise auth on this controller).
  #
  # Slice 1 behaviour: regardless of what arrives, reply «Hola desde Biblio»
  # and 200. Persistence, dedupe, linking, Claude all come in later slices.
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :touch_last_seen!, raise: false

    REPLY_HELLO = "Hola desde Biblio"

    def create
      return head :not_found unless valid_secret?

      chat_id = params.dig(:message, :chat, :id)
      Telegram::Client.send_message(chat_id: chat_id, text: REPLY_HELLO) if chat_id
      head :ok
    rescue Telegram::Client::Error => e
      # Don't 500 back at Telegram — they'd retry. Log and 200.
      Rails.logger.warn("[Telegram::WebhooksController] send failed: #{e.message}")
      head :ok
    end

    private

    def valid_secret?
      provided = params[:secret].to_s
      expected = Telegram::Config::WEBHOOK_SECRET
      return false if expected.blank?
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end
