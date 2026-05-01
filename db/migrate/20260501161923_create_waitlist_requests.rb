class CreateWaitlistRequests < ActiveRecord::Migration[8.0]
  # Public registration is closed; people interested in trying the app
  # leave their email here from the /users/sign_up page. Owner reviews
  # the table from the rails console and sends an Invitation when ready.
  def change
    create_table :waitlist_requests do |t|
      t.string :email, null: false
      t.text :note
      t.datetime :invited_at
      t.timestamps
    end
    add_index :waitlist_requests, :email, unique: true
    add_index :waitlist_requests, :created_at
  end
end
