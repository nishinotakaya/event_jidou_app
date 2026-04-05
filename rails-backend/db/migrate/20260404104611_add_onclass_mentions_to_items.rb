class AddOnclassMentionsToItems < ActiveRecord::Migration[7.2]
  def change
    add_column :items, :onclass_mentions, :text
    add_column :items, :onclass_channels, :text
    add_column :items, :student_post_type, :string
  end
end
