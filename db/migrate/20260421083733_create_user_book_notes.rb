class CreateUserBookNotes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    create_table :user_book_notes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.text :body, null: false, default: ""

      t.timestamps
    end

    add_index :user_book_notes, [:user_id, :book_id], unique: true, algorithm: :concurrently
  end
end
