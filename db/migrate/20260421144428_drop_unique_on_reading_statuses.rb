class DropUniqueOnReadingStatuses < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    remove_index :reading_statuses, name: "index_reading_statuses_on_user_id_and_book_id",
      algorithm: :concurrently, if_exists: true
    add_index :reading_statuses, [:user_id, :book_id, :created_at],
      order: {created_at: :desc}, algorithm: :concurrently, if_not_exists: true
  end
end
