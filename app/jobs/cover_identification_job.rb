class CoverIdentificationJob < ApplicationJob
  queue_as :default

  retry_on ClaudeCoverIdentifier::Error, wait: 15.seconds, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(cover_photo_id)
    cover_photo = CoverPhoto.find(cover_photo_id)
    cover_photo.update!(status: :processing, error_message: nil)
    broadcast(cover_photo)

    payload = ClaudeCoverIdentifier.call(cover_photo)
    cover_photo.update!(status: :completed, claude_raw_response: payload)
    broadcast(cover_photo)
  rescue ClaudeCoverIdentifier::Error, Timeout::Error => e
    cover_photo&.update!(status: :failed, error_message: e.message)
    broadcast(cover_photo) if cover_photo
    raise
  end

  private

  # Replaces the "Analizando…" placeholder in the add-book modal with
  # either the pre-filled form (on completion) or an error state.
  def broadcast(cover_photo)
    Turbo::StreamsChannel.broadcast_replace_to(
      [cover_photo, :status],
      target: "new-book-form",
      partial: partial_for(cover_photo),
      locals: {library: cover_photo.library, cover_photo: cover_photo, book: prefilled_book(cover_photo)}
    )
  end

  def partial_for(cover_photo)
    case cover_photo.status
    when "completed" then "books/new_modal_form"
    when "failed" then "cover_photos/identification_failed"
    else "cover_photos/analyzing"
    end
  end

  def prefilled_book(cover_photo)
    book = cover_photo.library.books.build
    return book unless cover_photo.completed?

    book.title = cover_photo.title.to_s
    book.subtitle = cover_photo.subtitle
    book.author = cover_photo.author
    book.publisher = cover_photo.publisher
    book.isbn = cover_photo.isbn
    book.published_year = cover_photo.published_year&.to_i
    book.page_count = cover_photo.page_count&.to_i
    book.language = cover_photo.language
    book.synopsis = cover_photo.synopsis
    book.cdu = cover_photo.cdu
    book.genres = cover_photo.genres
    book
  end
end
