class AddIntentToCoverPhotos < ActiveRecord::Migration[8.0]
  # Tracks where the identified Book should land. Default 0 = :library
  # (the existing flow). 1 = :wishlist (Telegram photo with a caption
  # like "wishlist", "para luego", "apunta"…).
  def change
    add_column :cover_photos, :intent, :integer, default: 0, null: false
  end
end
