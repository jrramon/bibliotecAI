class Invitation < ApplicationRecord
  belongs_to :library
  belongs_to :invited_by, class_name: "User"

  has_secure_token

  DEFAULT_TTL = 14.days

  validates :email, presence: true, format: URI::MailTo::EMAIL_REGEXP
  validates :email, uniqueness: {scope: :library_id, conditions: -> { where(accepted_at: nil) }, message: "ya fue invitado"}

  before_validation :set_defaults, on: :create
  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def accepted?
    accepted_at.present?
  end

  def claimable_by?(user)
    user.present? && user.email.casecmp?(email) && !expired? && !accepted?
  end

  def accept!(user)
    transaction do
      library.memberships.find_or_create_by!(user: user) { |m| m.role = :member }
      update!(accepted_at: Time.current)
    end
  end

  private

  def set_defaults
    self.expires_at ||= DEFAULT_TTL.from_now
  end
end
