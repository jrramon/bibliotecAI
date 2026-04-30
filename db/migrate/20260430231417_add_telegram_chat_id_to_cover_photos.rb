class AddTelegramChatIdToCoverPhotos < ActiveRecord::Migration[8.0]
  # Marks a CoverPhoto as having come from a Telegram message rather
  # than the web "add book" flow. CoverIdentificationJob uses its
  # presence as the signal to auto-create a Book and notify the user
  # in Telegram (instead of the in-page Turbo broadcast).
  def change
    add_column :cover_photos, :telegram_chat_id, :bigint
  end
end
