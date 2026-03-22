class AddTitleToZoomSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :zoom_settings, :title, :string
  end
end
