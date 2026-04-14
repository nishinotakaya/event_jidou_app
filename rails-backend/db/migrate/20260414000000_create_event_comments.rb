class CreateEventComments < ActiveRecord::Migration[7.1]
  def change
    create_table :event_comments do |t|
      t.string :item_id, null: false
      t.bigint :user_id
      t.string :user_name
      t.text :body, null: false
      t.timestamps
    end
    add_index :event_comments, :item_id
  end
end
