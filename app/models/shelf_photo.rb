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

  private

  def image_present
    errors.add(:image, "es obligatoria") unless image.attached?
  end

  def image_is_supported
    return if image.blob.content_type.in?(%w[image/jpeg image/png image/webp image/heic])
    errors.add(:image, "debe ser JPEG, PNG, WebP o HEIC")
  end
end
