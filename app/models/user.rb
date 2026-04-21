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
end
