module Telegram
  # Hooked into CoverIdentificationJob: when a CoverPhoto created from a
  # Telegram upload finishes processing, we either auto-create the Book
  # (if Claude was confident enough) or tell the user to take a look on
  # the web. The cover_photo carries `telegram_chat_id` set on intake by
  # the webhook — without it, this service doesn't run.
  class NotifyIdentifiedCover
    CONFIDENCE_FLOOR = 0.5

    def self.call(...) = new(...).call

    def initialize(cover_photo)
      @cover_photo = cover_photo
      @chat_id = cover_photo.telegram_chat_id
    end

    def call
      return if @chat_id.blank?

      case @cover_photo.status
      when "completed"
        return reply_low_confidence unless confident?
        @cover_photo.intent_wishlist? ? auto_add_to_wishlist : auto_add_to_library
      when "failed"
        reply_failed
      end
    end

    private

    def confident?
      @cover_photo.title.present? && @cover_photo.confidence.to_f >= CONFIDENCE_FLOOR
    end

    def auto_add_to_library
      book = build_book
      book.save!
      copy_cover_image(book)

      Telegram::Client.send_message(
        chat_id: @chat_id,
        text: "✓ He añadido «#{book.title}» a tu biblioteca «#{@cover_photo.library.name}»."
      )
    end

    def auto_add_to_wishlist
      title = @cover_photo.title
      author = @cover_photo.author.presence

      existing = WishlistItem.match_for(title: title, author: author, user_id: @cover_photo.uploaded_by_user_id, isbn: @cover_photo.isbn).first
      if existing
        Telegram::Client.send_message(
          chat_id: @chat_id,
          text: "«#{title}» ya estaba apuntado en tu wishlist."
        )
        return
      end

      WishlistItem.create!(
        user_id: @cover_photo.uploaded_by_user_id,
        title: title,
        author: author,
        isbn: @cover_photo.isbn
      )

      Telegram::Client.send_message(
        chat_id: @chat_id,
        text: "✓ He apuntado «#{title}» en tu wishlist."
      )
    end

    def build_book
      @cover_photo.library.books.new(
        added_by_user_id: @cover_photo.uploaded_by_user_id,
        title: @cover_photo.title,
        subtitle: @cover_photo.subtitle,
        author: @cover_photo.author,
        publisher: @cover_photo.publisher,
        isbn: @cover_photo.isbn,
        published_year: @cover_photo.published_year&.to_i,
        page_count: @cover_photo.page_count&.to_i,
        language: @cover_photo.language,
        synopsis: @cover_photo.synopsis,
        cdu: @cover_photo.cdu,
        genres: @cover_photo.genres
      )
    end

    # Reuse the photo the user sent as the cover image of the new Book.
    # Best-effort: if the attach fails, the book exists without a cover —
    # not a reason to abort the whole flow.
    def copy_cover_image(book)
      return unless @cover_photo.image.attached?
      blob = @cover_photo.image.blob
      book.cover_image.attach(io: StringIO.new(blob.download),
        filename: blob.filename.to_s,
        content_type: blob.content_type)
    rescue => e
      Rails.logger.warn("[NotifyIdentifiedCover] cover attach failed for book=#{book.id}: #{e.class}: #{e.message}")
    end

    def reply_low_confidence
      Telegram::Client.send_message(
        chat_id: @chat_id,
        text: "No conseguí identificar el libro con seguridad. Echa un vistazo en la web cuando puedas y lo ajustas a mano."
      )
    end

    def reply_failed
      Telegram::Client.send_message(
        chat_id: @chat_id,
        text: "Hubo un error procesando la foto. Vuelve a probar o súbela desde la web."
      )
    end
  end
end
