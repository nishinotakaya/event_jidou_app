class AddSessionDataToServiceConnections < ActiveRecord::Migration[7.2]
  def change
    add_column :service_connections, :session_data, :text
  end
end
