class CoverPhoto < ApplicationRecord
  belongs_to :library
  belongs_to :uploaded_by_user, class_name: "User"

  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_limit: [220, 330]
  end

  enum :status, {pending: 0, processing: 1, completed: 2, failed: 3}, default: :pending
  # Where the identified Book should be persisted: :library is the
  # existing web-upload behaviour; :wishlist is set by the Telegram
  # webhook when the photo caption hints "para luego".
  enum :intent, {library: 0, wishlist: 1}, prefix: :intent, default: :library

  validate :image_present
  validate :image_is_supported, if: -> { image.attached? }

  # Flat accessors into `claude_raw_response` so views don't need to know
  # the JSON shape. A completed photo yields the identified-book hash;
  # incomplete photos yield nil for every field.
  IDENTIFIED_FIELDS = %w[
    title subtitle author publisher isbn published_year
    page_count language synopsis cdu
  ].freeze

  IDENTIFIED_FIELDS.each do |field|
    define_method(field) do
      claude_raw_response&.dig(field).presence
    end
  end

  def genres
    Array(claude_raw_response&.dig("genres"))
  end

  def confidence
    claude_raw_response&.dig("confidence")&.to_f
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
