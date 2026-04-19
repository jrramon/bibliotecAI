class BookIdentificationJob < ApplicationJob
  queue_as :default

  # Placeholder — Slice 7 wires the Claude CLI call and book creation.
  def perform(shelf_photo_id)
    shelf_photo = ShelfPhoto.find(shelf_photo_id)
    shelf_photo.update!(status: :processing)
    # TODO(slice 7): ClaudeBookIdentifier.new.call(shelf_photo) → create books, mark completed, annotate image.
  end
end
