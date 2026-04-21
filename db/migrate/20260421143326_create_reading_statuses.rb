class CreateReadingStatuses < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :reading_statuses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :state, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :reading_statuses, [:user_id, :book_id], unique: true, algorithm: :concurrently
    add_index :reading_statuses, [:user_id, :state], algorithm: :concurrently
  end
end
