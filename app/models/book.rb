class Book < ApplicationRecord
  extend FriendlyId

  friendly_id :title, use: [:scoped, :slugged, :history], scope: :library

  belongs_to :library
  belongs_to :added_by_user, class_name: "User"

  has_one_attached :cover_image do |attachable|
    attachable.variant :card, resize_to_limit: [300, 450]
    attachable.variant :hero, resize_to_limit: [800, 1200]
  end

  has_many :comments, dependent: :destroy

  validates :title, presence: true, length: {maximum: 240}
  validates :author, length: {maximum: 180}, allow_blank: true
  validates :isbn, length: {maximum: 32}, allow_blank: true
  validates :goodreads_url, format: {with: URI::DEFAULT_PARSER.make_regexp(%w[http https])}, allow_blank: true
  validates :notes, length: {maximum: 4_000}, allow_blank: true
  validate :cover_image_is_supported

  scope :recent, -> { order(created_at: :desc) }

  # Transliterates + lowercases + collapses non-alphanum so that near-duplicate
  # titles from successive Claude passes ("1984" vs "1984 ", "Episodios
  # Nacionales" vs "episodios nacionales (primera serie)") can be deduped.
  def self.normalize(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
  end

  def search_key
    self.class.normalize(title)
  end

  private

  def cover_image_is_supported
    return unless cover_image.attached?
    return if cover_image.blob.content_type.in?(%w[image/jpeg image/png image/webp image/heic])
    errors.add(:cover_image, "debe ser JPEG, PNG, WebP o HEIC")
  end
end
