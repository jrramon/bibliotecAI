class CreateBooks < ActiveRecord::Migration[8.0]
  def change
    create_table :books do |t|
      t.references :library, null: false, foreign_key: true
      t.references :added_by_user, null: false, foreign_key: {to_table: :users}
      t.string :title, null: false
      t.string :author
      t.string :isbn
      t.string :goodreads_url
      t.text :notes
      t.string :slug, null: false
      t.float :confidence

      t.timestamps
    end

    add_index :books, [:library_id, :slug], unique: true
  end
end
