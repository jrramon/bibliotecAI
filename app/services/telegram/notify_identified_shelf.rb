module Telegram
  # Hooked into BookIdentificationJob: when a ShelfPhoto created from a
  # Telegram upload finishes processing, summarize the identified books
  # back to the user (with a link to the annotated image on the web)
  # or report failure. The shelf_photo carries `telegram_chat_id` set
  # by the MCP tool that staged it — without it, this service is a
  # no-op so web-only uploads stay quiet.
  class NotifyIdentifiedShelf
    PREVIEW_TITLES = 3

    def self.call(...) = new(...).call

    def initialize(shelf_photo)
      @shelf_photo = shelf_photo
      @chat_id = shelf_photo.telegram_chat_id
    end

    def call
      return if @chat_id.blank?

      case @shelf_photo.status
      when "completed"
        reply_completed
      when "failed"
        reply_failed
      end
    end

    private

    def reply_completed
      added = @shelf_photo.entries_above_threshold
      below = @shelf_photo.entries_below_threshold
      link = shelf_photo_link

      text = if added.empty?
        "No identifiqué ningún libro con seguridad en esta foto. Échale un vistazo: #{link}"
      else
        title_list = added.first(PREVIEW_TITLES).map { |e| "*#{e["title"]}*" }.join(", ")
        more = (added.size > PREVIEW_TITLES) ? " (y #{added.size - PREVIEW_TITLES} más)" : ""
        msg = "✅ He añadido #{added.size} libro#{"s" unless added.size == 1} a *#{@shelf_photo.library.name}*: #{title_list}#{more}."
        msg += if below.any?
          " Hay #{below.size} sin identificar — revísalos en la web: #{link}"
        else
          " Verlos: #{link}"
        end
        msg
      end

      Telegram::Client.send_message(chat_id: @chat_id, text: text)
    end

    def reply_failed
      Telegram::Client.send_message(
        chat_id: @chat_id,
        text: "Hubo un error procesando la foto de la estantería. Vuelve a probar o súbela desde la web."
      )
    end

    def shelf_photo_link
      Rails.application.routes.url_helpers.library_shelf_photo_url(
        library_id: @shelf_photo.library_id,
        id: @shelf_photo.id,
        host: web_host
      )
    end

    # Fall back to localhost when APP_HOSTS isn't set (test/dev). The
    # production deploy always sets APP_HOSTS — same source production.rb
    # uses for its hosts allowlist.
    def web_host
      ENV["APP_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?).first || "localhost:3000"
    end
  end
end
