class AddTelegramFieldsToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Both nullable: a user without a linked Telegram is the default state.
    add_column :users, :telegram_chat_id, :bigint unless column_exists?(:users, :telegram_chat_id)
    add_column :users, :telegram_username, :string unless column_exists?(:users, :telegram_username)

    # Unique so two users can't share a chat_id (would happen if A links,
    # later B clicks A's deep link by accident — we reject the second).
    add_index :users, :telegram_chat_id, unique: true, algorithm: :concurrently
  end
end
