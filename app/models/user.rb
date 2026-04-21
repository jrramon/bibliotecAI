class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  has_many :memberships, dependent: :destroy
  has_many :libraries, through: :memberships
  has_many :owned_libraries, class_name: "Library", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner
  has_many :comments, dependent: :destroy
  has_many :user_book_notes, dependent: :destroy
end
