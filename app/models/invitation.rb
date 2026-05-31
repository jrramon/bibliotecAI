class Invitation < ApplicationRecord
  belongs_to :library, optional: true
  belongs_to :invited_by, class_name: "User"

  has_secure_token

  DEFAULT_TTL = 14.days

  validates :email, presence: true, format: URI::MailTo::EMAIL_REGEXP
  validates :email, uniqueness: {scope: :library_id, conditions: -> { where(accepted_at: nil) }, message: "ya fue invitado"}

  before_validation :set_defaults, on: :create
  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }
  scope :unaccepted, -> { where(accepted_at: nil).order(:created_at) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def accepted?
    accepted_at.present?
  end

  # Pushes expires_at out to a fresh TTL so the owner can give a
  # distracted invitee another two weeks. Keeps the original token
  # intact — any earlier email the recipient already received still
  # works.
  def resend!
    update!(expires_at: DEFAULT_TTL.from_now)
  end

  def claimable_by?(user)
    user.present? && user.email.casecmp?(email) && !expired? && !accepted?
  end

  # Accepts the invitation and returns the library the user lands on.
  # With a library: joins it as :member (collaborator). Without one: this is
  # an account invitation, so we provision the user's own library (:owner via
  # Library's create_owner_membership callback).
  def accept!(user)
    transaction do
      target =
        if library
          library.memberships.find_or_create_by!(user: user) { |m| m.role = :member }
          library
        else
          user.owned_libraries.create!(
            name: "Biblioteca de #{user.name.presence || user.email.split("@").first}"
          )
        end
      update!(accepted_at: Time.current)
      target
    end
  end

  private

  def set_defaults
    self.expires_at ||= DEFAULT_TTL.from_now
  end
end
