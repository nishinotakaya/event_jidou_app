class AddExpiresAtToOnclassStudents < ActiveRecord::Migration[7.1]
  def change
    add_column :onclass_students, :expires_at, :date
    add_index :onclass_students, :expires_at
  end
end
