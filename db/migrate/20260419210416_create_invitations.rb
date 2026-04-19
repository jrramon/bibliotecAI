class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations do |t|
      t.references :library, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: {to_table: :users}
      t.string :email, null: false
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at

      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, [:library_id, :email], unique: true, where: "accepted_at IS NULL"
  end
end
