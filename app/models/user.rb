class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [80, 80], preprocessed: true
    attachable.variant :small, resize_to_fill: [44, 44]
  end

  validates :name, length: {maximum: 80}, allow_blank: true
  validate :avatar_is_supported, if: -> { avatar.attached? }

  # Display name for greetings, avatar initials, search hits. Prefers the
  # explicit `name` column, falls back to the local part of the email.
  def display_name
    name.presence || email.to_s.split("@").first.to_s
  end

  has_many :memberships, dependent: :destroy
  has_many :libraries, through: :memberships
  has_many :owned_libraries, class_name: "Library", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner
  has_many :comments, dependent: :destroy
  has_many :user_book_notes, dependent: :destroy
  has_many :reading_statuses, dependent: :destroy
  has_many :wishlist_items, dependent: :destroy
  has_many :reading_books, -> { merge(ReadingStatus.active) },
    through: :reading_statuses, source: :book

  # Distinct members (themselves + all other users) of every library the
  # viewer belongs to, whose email matches `query`. Scoping keeps the
  # global search private to each user's own tenants.
  def self.search_within_viewer_libraries(query, viewer:, limit: 10)
    return none if query.blank? || viewer.nil?
    term = "%#{sanitize_sql_like(query.downcase)}%"
    joins(:memberships)
      .where(memberships: {library_id: viewer.libraries.select(:id)})
      .where("LOWER(users.email) LIKE ?", term)
      .distinct
      .order(:email)
      .limit(limit)
  end

  private

  def avatar_is_supported
    return if avatar.blob.content_type.in?(%w[image/jpeg image/png image/webp image/heic])
    errors.add(:avatar, "debe ser JPEG, PNG, WebP o HEIC")
  end
end
