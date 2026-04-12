class CreateGeneratedImages < ActiveRecord::Migration[7.1]
  def change
    create_table :generated_images do |t|
      t.bigint :user_id
      t.string :source, null: false, default: 'dalle'
      t.string :filename
      t.string :content_type, default: 'image/png'
      t.integer :byte_size
      t.text :prompt
      t.string :style
      t.string :item_id
      t.binary :data, null: false, limit: 16.megabytes
      t.timestamps
    end
    add_index :generated_images, :user_id
    add_index :generated_images, :created_at
  end
end
