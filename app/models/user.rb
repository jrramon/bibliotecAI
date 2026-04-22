class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  has_many :memberships, dependent: :destroy
  has_many :libraries, through: :memberships
  has_many :owned_libraries, class_name: "Library", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner
  has_many :comments, dependent: :destroy
  has_many :user_book_notes, dependent: :destroy
  has_many :reading_statuses, dependent: :destroy
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
end
