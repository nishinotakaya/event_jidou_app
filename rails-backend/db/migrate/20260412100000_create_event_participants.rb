class CreateEventParticipants < ActiveRecord::Migration[7.1]
  def change
    create_table :event_participants do |t|
      t.string :item_id, null: false
      t.string :site_name, null: false
      t.string :name
      t.string :email
      t.timestamps
    end
    add_index :event_participants, [:item_id, :site_name]
  end
end
