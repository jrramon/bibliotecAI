module Telegram
  # Receives `update` POSTs from Telegram. The path-secret check authenticates
  # the call cheaply: only Telegram (and us, when we set the webhook) knows
  # the URL. CSRF is skipped because the caller has no Rails session, and
  # `authenticate_user!` is not in scope (no Devise auth on this controller).
  #
  # Behaviour by slice (current = 8):
  # - dedupe via Rails.cache + DB unique on `update_id` (Slice 2).
  # - private chats only (Slice 2).
  # - persist a TelegramMessage row per accepted update (Slice 2).
  # - `/start <token>` runs Telegram::Linker synchronously and replies
  #   with the linker's outcome (Slice 3).
  # - linked chats stamp `TelegramMessage.user_id` (Slice 3).
  # - any other text from a linked chat is queued as :pending; the host
  #   claude-worker drains it via TelegramMessageJob and replies (Slice 4).
  #   We send a "typing…" chat action up front so the user gets feedback
  #   while claude generates the answer.
  # - photos from a linked chat get downloaded inline and persisted as
  #   a CoverPhoto in the user's default library; CoverIdentificationJob
  #   later auto-creates the Book and replies via Telegram (Slice 8).
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :touch_last_seen!, raise: false

    REPLY_LINK_FIRST = "👋 Para hablar conmigo, primero vincula tu cuenta de BibliotecAI desde tu perfil web."
    REPLY_NO_LIBRARY = "Para añadir libros con foto, primero crea una biblioteca en BibliotecAI."
    REPLY_PHOTO_RECEIVED_LIBRARY = "📸 Foto recibida. La estoy analizando para añadir el libro a tu biblioteca."
    REPLY_PHOTO_RECEIVED_WISHLIST = "📸 Foto recibida. La estoy analizando para apuntar el libro en tu wishlist."
    REPLY_PHOTO_FAILED = "No he podido procesar la foto. Vuelve a probar o súbela desde la web."
    REPLY_THROTTLED = "⚠️ Has alcanzado el límite de mensajes por hora. Vuelve a probar dentro de un rato."
    DEDUPE_TTL = 10.minutes
    THROTTLE_LIMIT = 60
    THROTTLE_WINDOW = 90.minutes # bucket TTL — actual reset is hourly via the key
    START_RE = /\A\/start(?:\s+(\S+))?\z/
    # Captions that route the photo to the wishlist instead of the
    # library. Anything else (or empty caption) → library.
    WISHLIST_CAPTION_RE = /\b(wishlist|wish|deseo|deseos|para\s+luego|para\s+m[aá]s\s+tarde|apunta|ap[uú]ntalo)\b/i

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
          "kind=#{message[:photo].present? ? "photo" : "text"} " \
          "text=#{text.inspect.truncate(120)}"
        )
        Telegram::Client.send_message(chat_id: chat_id, text: REPLY_LINK_FIRST)
        return head :ok
      end

      if throttle_exceeded?(user.id)
        Rails.logger.info("[Telegram::WebhooksController] throttled user=#{user.id} chat=#{chat_id}")
        Telegram::Client.send_message(chat_id: chat_id, text: REPLY_THROTTLED)
        return head :ok
      end

      if message[:photo].present?
        handle_photo(user: user, chat_id: chat_id, message: message)
        return head :ok
      end

      enqueue_for_claude(user: user, chat_id: chat_id, update_id: update_id, text: text)
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

    # Linked chat sent regular text. The actual answer is generated by
    # the host claude-worker — we just persist :pending and ping a
    # typing indicator so the user knows we're on it.
    def enqueue_for_claude(user:, chat_id:, update_id:, text:)
      TelegramMessage.create!(
        user: user,
        chat_id: chat_id,
        update_id: update_id,
        text: text,
        status: :pending
      )

      begin
        Telegram::Client.send_chat_action(chat_id: chat_id, action: "typing")
      rescue Telegram::Client::Error => e
        # Cosmetic: don't 500 the webhook just because typing didn't ship.
        Rails.logger.warn("[Telegram::WebhooksController] typing failed: #{e.message}")
      end
    end

    # Telegram photo messages carry an array of progressively higher
    # resolutions in `message[:photo]`. The last one is the original.
    # We download it inline (the bytes fit in 1-2s for a typical phone
    # photo) so the CoverPhoto can be persisted with an attachment ready
    # for the host worker to pick up.
    #
    # The optional `caption` decides where the identified Book lands:
    # captions matching WISHLIST_CAPTION_RE route to the wishlist; any
    # other caption (or no caption) routes to the user's default library.
    def handle_photo(user:, chat_id:, message:)
      library = user.default_library
      unless library
        Telegram::Client.send_message(chat_id: chat_id, text: REPLY_NO_LIBRARY)
        return
      end

      sizes = Array(message[:photo])
      best = sizes.max_by { |s| s[:file_size].to_i }
      file_id = best&.dig(:file_id)
      return unless file_id

      file_info = Telegram::Client.get_file(file_id: file_id)
      bytes = Telegram::Client.download_file(file_path: file_info["file_path"])

      intent = wishlist_caption?(message[:caption]) ? :wishlist : :library

      cover_photo = library.cover_photos.build(
        uploaded_by_user: user,
        telegram_chat_id: chat_id,
        intent: intent
      )
      cover_photo.image.attach(
        io: StringIO.new(bytes),
        filename: "telegram_#{file_id}.jpg",
        content_type: "image/jpeg"
      )
      cover_photo.save!

      reply = (intent == :wishlist) ? REPLY_PHOTO_RECEIVED_WISHLIST : REPLY_PHOTO_RECEIVED_LIBRARY
      Telegram::Client.send_message(chat_id: chat_id, text: reply)
    rescue Telegram::Client::Error, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Telegram::WebhooksController] photo intake failed: #{e.class}: #{e.message}")
      begin
        Telegram::Client.send_message(chat_id: chat_id, text: REPLY_PHOTO_FAILED)
      rescue Telegram::Client::Error
        # Already in trouble — give up silently.
      end
    end

    def wishlist_caption?(caption)
      caption.to_s.match?(WISHLIST_CAPTION_RE)
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

    # Hourly bucket per user. Keyed by the current UTC hour so the count
    # auto-resets at the top of each hour without a sweep job. We don't
    # persist the count per-message in the DB on purpose: this is purely
    # a cost guardrail for the Claude calls behind it; a deny-listed
    # request leaves no trace beyond a log line.
    def throttle_exceeded?(user_id)
      key = "tg:throttle:#{user_id}:#{Time.current.utc.strftime('%Y%m%d%H')}"
      count = Rails.cache.read(key).to_i
      return true if count >= THROTTLE_LIMIT
      Rails.cache.write(key, count + 1, expires_in: THROTTLE_WINDOW)
      false
    end
  end
end
