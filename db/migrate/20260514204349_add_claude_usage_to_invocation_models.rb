class AddClaudeUsageToInvocationModels < ActiveRecord::Migration[8.0]
  def change
    add_column :shelf_photos,      :claude_usage, :jsonb
    add_column :cover_photos,      :claude_usage, :jsonb
    add_column :telegram_messages, :claude_usage, :jsonb
  end
end
