module Telegram
  # Receives `update` POSTs from Telegram. The path-secret check authenticates
  # the call cheaply: only Telegram (and us, when we set the webhook) knows
  # the URL. CSRF is skipped because the caller has no Rails session, and
  # `authenticate_user!` is not in scope (no Devise auth on this controller).
  #
  # Behaviour by slice (current = 3):
  # - dedupe via Rails.cache + DB unique on `update_id` (Slice 2).
  # - private chats only (Slice 2).
  # - persist a TelegramMessage row per accepted update (Slice 2).
  # - `/start <token>` runs Telegram::Linker before anything else and
  #   replies with the linker's outcome (Slice 3, this slice).
  # - linked chats stamp `TelegramMessage.user_id` (Slice 3).
  # - any other text from a linked or unlinked chat still gets the
  #   hardcoded «Hola desde Biblio». Claude lands in Slice 4.
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :touch_last_seen!, raise: false

    REPLY_HELLO = "Hola desde Biblio"
    REPLY_LINK_FIRST = "👋 Para hablar conmigo, primero vincula tu cuenta de BibliotecAI desde tu perfil web."
    DEDUPE_TTL = 10.minutes
    START_RE = /\A\/start(?:\s+(\S+))?\z/

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

      if (match = START_RE.match(text))
        # /start <token>: always processed, even from unlinked chats —
        # this is how a chat *becomes* linked.
        username = message.dig(:from, :username)
        reply = Telegram::Linker.call(token: match[1].to_s, chat_id: chat_id, username: username).message
        user = User.find_by(telegram_chat_id: chat_id) # may now be set
        persist_and_reply(user: user, chat_id: chat_id, update_id: update_id, text: text, reply: reply)
        return head :ok
      end

      user = User.find_by(telegram_chat_id: chat_id)
      unless user
        # Unlinked chat sending a non-/start message. Log for forensics
        # but skip DB write so random Telegram users can't fill our table.
        Rails.logger.info(
          "[Telegram::WebhooksController] unlinked chat=#{chat_id} ignored: " \
          "text=#{text.inspect.truncate(120)}"
        )
        Telegram::Client.send_message(chat_id: chat_id, text: REPLY_LINK_FIRST)
        return head :ok
      end

      persist_and_reply(user: user, chat_id: chat_id, update_id: update_id, text: text, reply: REPLY_HELLO)
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

    def persist_and_reply(user:, chat_id:, update_id:, text:, reply:)
      TelegramMessage.create!(
        user: user,
        chat_id: chat_id,
        update_id: update_id,
        text: text,
        status: :completed,
        bot_reply: reply
      )
      Telegram::Client.send_message(chat_id: chat_id, text: reply)
    end

    def valid_secret?
      provided = params[:secret].to_s
      expected = Telegram::Config::WEBHOOK_SECRET
      return false if expected.blank?
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end

    def first_time?(update_id)
      Rails.cache.write("tg:update:#{update_id}", true,
        unless_exist: true,
        expires_in: DEDUPE_TTL)
    end
  end
end
