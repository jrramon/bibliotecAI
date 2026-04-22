class UserBookNote < ApplicationRecord
  belongs_to :user
  belongs_to :book

  validates :user_id, uniqueness: {scope: :book_id}
  validates :body, length: {maximum: 4_000}

  # Viewer's own notes whose body matches `query`. Private by design:
  # the global search never reveals other users' notes.
  def self.search_for_viewer(query, viewer:, limit: 10)
    return none if query.blank? || viewer.nil?
    term = "%#{sanitize_sql_like(query.downcase)}%"
    where(user_id: viewer.id)
      .where("LOWER(COALESCE(body, '')) LIKE ?", term)
      .where.not(body: [nil, ""])
      .includes(book: :library)
      .order(updated_at: :desc)
      .limit(limit)
  end
end
