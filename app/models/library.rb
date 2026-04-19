class Library < ApplicationRecord
  extend FriendlyId

  friendly_id :name, use: [:slugged, :history]

  belongs_to :owner, class_name: "User"
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy

  validates :name, presence: true, length: {maximum: 120}
  validates :description, length: {maximum: 1_000}, allow_blank: true

  after_create :create_owner_membership

  private

  def create_owner_membership
    memberships.create!(user: owner, role: :owner)
  end
end
