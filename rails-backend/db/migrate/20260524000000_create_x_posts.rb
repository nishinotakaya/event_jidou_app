class CreateXPosts < ActiveRecord::Migration[7.2]
  def change
    create_table :x_posts do |t|
      t.bigint  :user_id,       null: false
      t.text    :content,       null: false
      t.string  :image_url
      t.datetime :scheduled_at, null: false
      t.string  :status,        null: false, default: 'pending'
      t.datetime :posted_at
      t.string  :tweet_id
      t.string  :tweet_url
      t.text    :error_message
      t.string  :item_id
      t.string  :source,        default: 'manual'
      t.timestamps
    end

    add_index :x_posts, [:user_id, :scheduled_at]
    add_index :x_posts, [:status, :scheduled_at]
    add_index :x_posts, :item_id
  end
end
