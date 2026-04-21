class AddSpineFieldsToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :stamp, :string, limit: 4 unless column_exists?(:books, :stamp)
    add_column :books, :spine_palette, :integer unless column_exists?(:books, :spine_palette)
  end
end
