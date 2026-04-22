class WishlistItem < ApplicationRecord
  belongs_to :user

  validates :title, presence: true, length: {maximum: 240}
  validates :author, length: {maximum: 180}, allow_blank: true
  validates :isbn, length: {maximum: 32}, allow_blank: true
  validates :note, length: {maximum: 240}, allow_blank: true

  before_validation :recompute_normalized_key

  scope :recent, -> { order(created_at: :desc) }

  # Matches a book's title + author (normalized) and/or ISBN against the
  # wishlist. Used by Book#prune_matching_wishlist_items when a Book is
  # created to delete any wishlist entries that have become redundant.
  # Accepts either `user:` (User instance) or `user_id:` (integer).
  def self.match_for(title:, author:, user: nil, user_id: nil, isbn: nil)
    uid = user_id || user&.id
    return none unless uid
    key_hash = normalized_key_hash_for(title, author)
    by_key = where(user_id: uid, normalized_key_hash: key_hash)
    return by_key if isbn.blank?

    # Double layer: also match by ISBN so a wishlist item added with a
    # slightly different title/author (e.g. "Sanshiro" vs "Sanshirō: A Novel")
    # still gets pruned when the Book lands with the same ISBN.
    by_isbn = where(user_id: uid, isbn: isbn.to_s.strip)
    where(id: by_key.select(:id)).or(where(id: by_isbn.select(:id)))
  end

  def self.normalized_key_hash_for(title, author)
    Book.normalize("#{title} #{author}").hash
  end

  private

  def recompute_normalized_key
    self.normalized_key_hash = self.class.normalized_key_hash_for(title, author)
  end
end
