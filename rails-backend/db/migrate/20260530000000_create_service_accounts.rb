class CreateServiceAccounts < ActiveRecord::Migration[7.2]
  # 1 サービスに複数アカウント（X サブ垢・IG 複数運用）を持てるようにする土台。
  # 既存 service_connections（1ユーザー1サービス1接続）はレガシーとして残し、
  # service_accounts が無いサービスは従来どおり service_connections にフォールバックする。
  def change
    create_table :service_accounts do |t|
      t.references :user, foreign_key: true
      t.string  :service_name, null: false   # x / instagram / ...
      t.string  :label                        # 「メイン垢」「サブ垢」など表示名
      t.string  :handle                       # @screen_name など（任意・表示用）
      t.text    :session_data                 # トークン型（x: auth_token/ct0 の JSON）
      t.string  :email                        # ID/PW 型サービス用
      t.string  :encrypted_password_field
      t.string  :encrypted_password_field_iv
      t.string  :status, default: 'disconnected'
      t.boolean :is_active, default: false, null: false  # そのサービスの既定アカウント
      t.datetime :last_connected_at
      t.text    :error_message
      t.timestamps
    end

    add_index :service_accounts, [:user_id, :service_name]
  end
end
