class CreateServiceConnections < ActiveRecord::Migration[7.2]
  def change
    create_table :service_connections do |t|
      t.references :user, null: true, foreign_key: true
      t.string :service_name
      t.string :email
      t.string :encrypted_password_field
      t.string :encrypted_password_field_iv
      t.string :status
      t.datetime :last_connected_at
      t.text :error_message

      t.timestamps
    end
    add_index :service_connections, [:user_id, :service_name], unique: true
  end
end
