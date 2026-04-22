class AddWishlistShareTokenToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :users, :wishlist_share_token, :string unless column_exists?(:users, :wishlist_share_token)
    add_index :users, :wishlist_share_token, unique: true, algorithm: :concurrently
  end
end
