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
  has_many :user_book_notes, dependent: :destroy

  def note_for(user)
    return nil unless user
    user_book_notes.find_or_initialize_by(user: user)
  end

  validates :title, presence: true, length: {maximum: 240}
  validates :subtitle, length: {maximum: 240}, allow_blank: true
  validates :author, length: {maximum: 180}, allow_blank: true
  validates :publisher, length: {maximum: 180}, allow_blank: true
  validates :isbn, length: {maximum: 32}, allow_blank: true
  validates :cdu, length: {maximum: 32}, allow_blank: true
  validates :language, length: {maximum: 8}, allow_blank: true
  validates :google_books_id, length: {maximum: 32}, allow_blank: true
  validates :published_year, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: -> { Date.current.year + 1 }}, allow_nil: true
  validates :page_count, numericality: {only_integer: true, greater_than: 0, less_than: 100_000}, allow_nil: true
  validates :goodreads_url, format: {with: URI::DEFAULT_PARSER.make_regexp(%w[http https])}, allow_blank: true
  validates :notes, length: {maximum: 4_000}, allow_blank: true
  validates :synopsis, length: {maximum: 5_000}, allow_blank: true
  validate :cover_image_is_supported

  normalizes :genres, with: ->(values) {
    Array(values).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:empty?).uniq
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :with_cdu, ->(code) { where("cdu LIKE ?", "#{code}%") }
  scope :with_genre, ->(g) { where("? = ANY(genres)", g) }

  # Searches a library's books by title, synopsis, and — scoped to the
  # viewer — their own personal notes. Empty query returns everything.
  def self.search_in_library(library, query:, viewer:)
    scope = library.books
    return scope if query.blank?

    term = "%#{sanitize_sql_like(query.downcase)}%"
    scope
      .left_joins(:user_book_notes)
      .where(
        "LOWER(books.title) LIKE :t " \
        "OR LOWER(COALESCE(books.synopsis, '')) LIKE :t " \
        "OR (user_book_notes.user_id = :uid AND LOWER(COALESCE(user_book_notes.body, '')) LIKE :t)",
        t: term, uid: viewer&.id
      )
      .distinct
  end

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
