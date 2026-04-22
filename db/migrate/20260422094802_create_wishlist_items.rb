class CreateWishlistItems < ActiveRecord::Migration[8.0]
  def change
    create_table :wishlist_items do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :author
      t.string :isbn
      t.string :note
      t.string :google_books_id
      t.string :thumbnail_url
      # normalized(title + author).hash, stored as bigint so the full
      # Integer#hash fits. Used as the fast equality check for the
      # auto-prune callback on Book creation.
      t.bigint :normalized_key_hash, null: false

      t.timestamps
    end

    add_index :wishlist_items, [:user_id, :normalized_key_hash]
  end
end
