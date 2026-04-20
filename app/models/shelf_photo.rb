class ShelfPhoto < ApplicationRecord
  belongs_to :library
  belongs_to :uploaded_by_user, class_name: "User"

  has_one_attached :image do |attachable|
    attachable.variant :card, resize_to_limit: [600, 600]
    attachable.variant :hero, resize_to_limit: [1400, 1400]
  end
  has_one_attached :annotated_image do |attachable|
    attachable.variant :hero, resize_to_limit: [1400, 1400]
  end

  enum :status, {pending: 0, processing: 1, completed: 2, failed: 3}, default: :pending

  validate :image_present
  validate :image_is_supported, if: -> { image.attached? }

  scope :recent, -> { order(created_at: :desc) }

  def identified_entries
    Array(claude_raw_response&.dig("books"))
  end

  def unidentified_boxes
    Array(claude_raw_response&.dig("unidentified"))
  end

  def entries_above_threshold
    identified_entries.select { |e| (e["confidence"] || 0).to_f >= BookIdentificationJob::CONFIDENCE_THRESHOLD }
  end

  def entries_below_threshold
    identified_entries.reject { |e| (e["confidence"] || 0).to_f >= BookIdentificationJob::CONFIDENCE_THRESHOLD }
  end

  # Matches an identified entry back to an actual Book row in the library
  # via normalized title — `nil` if we dropped it (e.g. deduped, below threshold).
  def matching_book(entry)
    @books_by_key ||= library.books.index_by { |b| Book.normalize(b.title) }
    @books_by_key[Book.normalize(entry["title"])]
  end

  private

  def image_present
    errors.add(:image, "es obligatoria") unless image.attached?
  end

  def image_is_supported
    return if image.blob.content_type.in?(%w[image/jpeg image/png image/webp image/heic])
    errors.add(:image, "debe ser JPEG, PNG, WebP o HEIC")
  end
end
