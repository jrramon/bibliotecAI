class AddTelegramChatIdToShelfPhotos < ActiveRecord::Migration[8.0]
  # Marks a ShelfPhoto as having come from a Telegram message rather
  # than the web upload flow. BookIdentificationJob uses its presence
  # as the signal to fire Telegram::NotifyIdentifiedShelf with the
  # results (instead of relying on the in-page Turbo broadcast).
  def change
    add_column :shelf_photos, :telegram_chat_id, :bigint
  end
end
