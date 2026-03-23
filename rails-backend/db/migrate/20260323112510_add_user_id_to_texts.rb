class AddUserIdToTexts < ActiveRecord::Migration[7.2]
  def change
    add_reference :items, :user, null: true, foreign_key: true
  end
end
