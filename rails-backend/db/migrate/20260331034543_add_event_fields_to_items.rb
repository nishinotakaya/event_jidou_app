class AddEventFieldsToItems < ActiveRecord::Migration[7.2]
  def change
    add_column :items, :event_date, :string
    add_column :items, :event_time, :string
    add_column :items, :event_end_time, :string
  end
end
