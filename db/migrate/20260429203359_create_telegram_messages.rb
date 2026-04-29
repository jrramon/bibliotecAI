class CreateTelegramMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_messages do |t|
      # Nullable: until linking lands (Slice 3) the controller doesn't know
      # which User a chat belongs to. After Slice 3 it'll be populated for
      # any chat that's been linked, otherwise stay null.
      t.references :user, foreign_key: true, null: true

      # `chat_id` is where we send replies. For private chats Telegram
      # guarantees `chat.id == from.id`; we still store the chat_id since
      # that's what `sendMessage` wants.
      t.bigint :chat_id, null: false

      # Telegram's monotonically-increasing per-bot id. Unique index =
      # idempotency backstop if Telegram retries the same update before
      # our Rails.cache marker lands.
      t.bigint :update_id, null: false

      # Empty string is allowed (e.g. media-only message). NOT NULL keeps
      # the schema consistent — controller writes "" rather than nil.
      t.text :text, null: false

      # 0 pending / 1 processing / 2 completed / 3 failed (enum on the
      # model). Slice 2 always lands at :completed because the reply is
      # still inline in the controller. Slice 4 introduces real :pending.
      t.integer :status, default: 0, null: false

      t.text :bot_reply
      t.text :error_message

      t.timestamps
    end

    # Indexes outside create_table — strong_migrations allows
    # non-concurrent indexes on a brand-new (empty) table.
    add_index :telegram_messages, :update_id, unique: true
    add_index :telegram_messages, [:status, :created_at]
  end
end
