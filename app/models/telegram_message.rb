class TelegramMessage < ApplicationRecord
  belongs_to :user, optional: true

  # Photos forwarded from Telegram are attached here so the LLM-driven
  # MCP tools (process_book_cover_photo / process_shelf_photo) can
  # decide what to do with them. The webhook downloads the bytes once
  # and attaches them; downstream tools copy the blob into the proper
  # CoverPhoto/ShelfPhoto when invoked.
  has_one_attached :photo

  enum :status, {pending: 0, processing: 1, completed: 2, failed: 3}, default: :pending

  validates :chat_id, presence: true
  validates :update_id, presence: true, uniqueness: true
  validates :text, length: {maximum: 4_096}, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }
end
