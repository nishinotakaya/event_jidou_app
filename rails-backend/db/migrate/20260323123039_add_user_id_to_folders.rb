class AddUserIdToFolders < ActiveRecord::Migration[7.2]
  def change
    add_reference :folders, :user, null: true, foreign_key: true
  end
end
