class AddMetadataFieldsToBooks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :books, :subtitle, :string, limit: 240 unless column_exists?(:books, :subtitle)
    add_column :books, :synopsis, :text unless column_exists?(:books, :synopsis)
    add_column :books, :publisher, :string, limit: 180 unless column_exists?(:books, :publisher)
    add_column :books, :published_year, :integer unless column_exists?(:books, :published_year)
    add_column :books, :page_count, :integer unless column_exists?(:books, :page_count)
    add_column :books, :language, :string, limit: 8 unless column_exists?(:books, :language)
    add_column :books, :google_books_id, :string, limit: 32 unless column_exists?(:books, :google_books_id)

    add_index :books, :language, where: "language IS NOT NULL AND language <> ''",
      algorithm: :concurrently, if_not_exists: true
    add_index :books, :published_year, where: "published_year IS NOT NULL",
      algorithm: :concurrently, if_not_exists: true
    add_index :books, :google_books_id, where: "google_books_id IS NOT NULL AND google_books_id <> ''",
      algorithm: :concurrently, if_not_exists: true
  end
end
