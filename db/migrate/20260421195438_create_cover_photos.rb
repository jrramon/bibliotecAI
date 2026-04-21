class CreateCoverPhotos < ActiveRecord::Migration[8.0]
  def change
    create_table :cover_photos do |t|
      t.references :library, null: false, foreign_key: true
      t.references :uploaded_by_user, null: false, foreign_key: {to_table: :users}
      t.integer :status, null: false, default: 0
      t.jsonb :claude_raw_response
      t.text :error_message

      t.timestamps
    end

    add_index :cover_photos, [:library_id, :created_at]
  end
end
