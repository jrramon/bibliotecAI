class BookIdentificationJob < ApplicationJob
  queue_as :default

  retry_on ClaudeBookIdentifier::Error, wait: 30.seconds, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  CONFIDENCE_THRESHOLD = 0.5

  def perform(shelf_photo_id)
    shelf_photo = ShelfPhoto.find(shelf_photo_id)
    shelf_photo.update!(status: :processing, error_message: nil)
    broadcast(shelf_photo)

    result = ClaudeBookIdentifier.call(shelf_photo)
    create_books(shelf_photo, result.books)
    ShelfImageAnnotator.call(
      shelf_photo,
      result.unidentified,
      reported_width: result.image_width,
      reported_height: result.image_height
    )

    shelf_photo.update!(
      status: :completed,
      claude_raw_response: result.raw
    )
    broadcast(shelf_photo)
  rescue ClaudeBookIdentifier::Error, Timeout::Error => e
    shelf_photo&.update!(status: :failed, error_message: e.message)
    broadcast(shelf_photo) if shelf_photo
    raise
  end

  private

  def create_books(shelf_photo, entries)
    existing = shelf_photo.library.books.index_by { |b| Book.normalize(b.title) }

    entries.each do |entry|
      next unless entry["title"].to_s.present?
      next if (entry["confidence"] || 0).to_f < CONFIDENCE_THRESHOLD

      key = Book.normalize(entry["title"])

      if (book = existing[key])
        # Don't dupe the Book, but enrich any classification we couldn't nail
        # the first time Claude saw the shelf.
        book.update(cdu: entry["cdu"]) if book.cdu.blank? && entry["cdu"].present?
        book.update(genres: entry["genres"]) if book.genres.empty? && entry["genres"].present?
        next
      end

      created = shelf_photo.library.books.create!(
        title: entry["title"].to_s,
        author: entry["author"].to_s,
        confidence: entry["confidence"]&.to_f,
        cdu: entry["cdu"].presence,
        genres: Array(entry["genres"]),
        added_by_user: shelf_photo.uploaded_by_user
      )
      existing[key] = created

      fetch_cover_async(created)
    end
  end

  def fetch_cover_async(book)
    BookCoverFetcher.call(book)
  rescue => e
    Rails.logger.warn("[BookIdentificationJob] cover fetch for ##{book.id} failed: #{e.class}: #{e.message}")
  end

  def broadcast(shelf_photo)
    Turbo::StreamsChannel.broadcast_replace_to(
      [shelf_photo.library, :shelf_photos],
      target: ActionView::RecordIdentifier.dom_id(shelf_photo, :status),
      partial: "shelf_photos/status_badge",
      locals: {shelf_photo: shelf_photo}
    )
  end
end
