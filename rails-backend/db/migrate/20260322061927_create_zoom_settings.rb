class CreateZoomSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :zoom_settings do |t|
      t.string :zoom_url
      t.string :meeting_id
      t.string :passcode
      t.string :label

      t.timestamps
    end
  end
end
