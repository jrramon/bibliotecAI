class UserBookNote < ApplicationRecord
  belongs_to :user
  belongs_to :book

  validates :user_id, uniqueness: {scope: :book_id}
  validates :body, length: {maximum: 4_000}
end
