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
    ShelfImageAnnotator.call(shelf_photo, result.unidentified)

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
    existing_keys = shelf_photo.library.books.pluck(:title).map { |t| Book.normalize(t) }.to_set

    entries.each do |entry|
      next unless entry["title"].to_s.present?
      next if (entry["confidence"] || 0).to_f < CONFIDENCE_THRESHOLD

      key = Book.normalize(entry["title"])
      next if existing_keys.include?(key)
      existing_keys << key

      shelf_photo.library.books.create!(
        title: entry["title"].to_s,
        author: entry["author"].to_s,
        confidence: entry["confidence"]&.to_f,
        added_by_user: shelf_photo.uploaded_by_user
      )
    end
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
