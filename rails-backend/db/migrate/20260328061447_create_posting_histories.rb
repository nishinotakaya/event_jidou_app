class CreatePostingHistories < ActiveRecord::Migration[7.2]
  def change
    create_table :posting_histories do |t|
      t.string :item_id, null: false
      t.string :site_name, null: false
      t.string :status, null: false, default: 'success'
      t.string :event_url
      t.boolean :published, default: false
      t.text :error_message
      t.datetime :posted_at
      t.integer :user_id

      t.timestamps
    end
    add_index :posting_histories, :item_id
    add_index :posting_histories, [:item_id, :site_name]
  end
end
