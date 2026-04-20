class AddCduAndGenresToBooks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :books, :cdu, :string, limit: 32 unless column_exists?(:books, :cdu)
    add_column :books, :genres, :string, array: true, default: [] unless column_exists?(:books, :genres)
    add_index :books, :cdu, where: "cdu IS NOT NULL AND cdu <> ''",
      algorithm: :concurrently, if_not_exists: true
    add_index :books, :genres, using: :gin,
      algorithm: :concurrently, if_not_exists: true
  end
end
