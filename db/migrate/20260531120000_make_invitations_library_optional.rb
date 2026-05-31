class MakeInvitationsLibraryOptional < ActiveRecord::Migration[8.0]
  def change
    # A library-less invitation onboards an independent user: on accept it
    # provisions their own library instead of joining someone else's.
    change_column_null :invitations, :library_id, true
  end
end
