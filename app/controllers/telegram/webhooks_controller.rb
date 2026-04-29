module Telegram
  # Receives `update` POSTs from Telegram. The path-secret check authenticates
  # the call cheaply: only Telegram (and us, when we set the webhook) knows
  # the URL. CSRF is skipped because the caller has no Rails session, and
  # `authenticate_user!` is not in scope (no Devise auth on this controller).
  #
  # Slice 2 behaviour:
  # - dedupe: Rails.cache holds `update_id` 10 min so a Telegram retry
  #   within that window is a no-op. The DB unique index on
  #   `telegram_messages.update_id` is the backstop if the cache misses.
  # - filter: only private chats get processed. Groups + callback_query +
  #   edited_message + anything-else are silently ignored.
  # - persist: every accepted update creates a TelegramMessage row.
  # - reply: still hardcoded «Hola desde Biblio» (Claude lands in Slice 4).
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :touch_last_seen!, raise: false

    REPLY_HELLO = "Hola desde Biblio"
    DEDUPE_TTL = 10.minutes

    def create
      return head :not_found unless valid_secret?

      update_id = params[:update_id]
      return head :ok if update_id.blank?
      return head :ok unless first_time?(update_id)

      message = params[:message]
      chat = message&.dig(:chat)
      return head :ok if chat.blank? || chat[:type] != "private"

      chat_id = chat[:id]
      text = message[:text].to_s

      TelegramMessage.create!(
        chat_id: chat_id,
        update_id: update_id,
        text: text,
        status: :completed,
        bot_reply: REPLY_HELLO
      )
      Telegram::Client.send_message(chat_id: chat_id, text: REPLY_HELLO)
      head :ok
    rescue ActiveRecord::RecordNotUnique
      # Cache miss + DB unique caught the dupe. Telegram is satisfied with 200.
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

    # Returns true the first time we see this update_id, false on retries.
    # `unless_exist: true` makes the write atomic: it only succeeds if the
    # key wasn't already there.
    def first_time?(update_id)
      Rails.cache.write("tg:update:#{update_id}", true,
        unless_exist: true,
        expires_in: DEDUPE_TTL)
    end
  end
end
