class AddZoomUrlToItems < ActiveRecord::Migration[7.2]
  def change
    add_column :items, :zoom_url, :string
  end
end
