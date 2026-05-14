class Library < ApplicationRecord
  extend FriendlyId

  friendly_id :name, use: [:slugged, :history]

  belongs_to :owner, class_name: "User"
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_many :books, dependent: :destroy
  has_many :shelf_photos, dependent: :destroy
  has_many :cover_photos, dependent: :destroy

  validates :name, presence: true, length: {maximum: 120}
  validates :description, length: {maximum: 1_000}, allow_blank: true

  after_create :create_owner_membership

  # Returns [[genre, count], ...] for every distinct genre present across
  # this library's books, sorted by popularity (count desc) then name asc.
  def book_genres_with_counts
    books
      .where("array_length(genres, 1) > 0")
      .pluck(Arel.sql("UNNEST(genres)"))
      .tally
      .to_a
      .sort_by { |name, count| [-count, name.downcase] }
  end

  private

  def create_owner_membership
    memberships.create!(user: owner, role: :owner)
  end
end
