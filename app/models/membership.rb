class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :library

  enum :role, {owner: 0, member: 1}, default: :member

  validates :user_id, uniqueness: {scope: :library_id}
end
