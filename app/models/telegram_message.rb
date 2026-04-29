class TelegramMessage < ApplicationRecord
  belongs_to :user, optional: true

  enum :status, {pending: 0, processing: 1, completed: 2, failed: 3}, default: :pending

  validates :chat_id, presence: true
  validates :update_id, presence: true, uniqueness: true
  validates :text, length: {maximum: 4_096}, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }
end
