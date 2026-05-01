class WaitlistRequest < ApplicationRecord
  validates :email, presence: true, format: URI::MailTo::EMAIL_REGEXP, length: {maximum: 240}
  validates :email, uniqueness: {case_sensitive: false}
  validates :note, length: {maximum: 500}, allow_blank: true

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  scope :pending_invite, -> { where(invited_at: nil).order(:created_at) }
end
