class ServiceAccount < ApplicationRecord
  # 1 サービス複数アカウント運用の単位（X サブ垢・IG 複数など）。
  # 既存 ServiceConnection（1サービス1接続）と共存し、フォールバック関係にある。
  belongs_to :user, optional: true

  attr_encrypted :password_field,
                 key: ->(_) { ENV.fetch('ENCRYPTION_KEY', '0' * 64)[0, 32] },
                 algorithm: 'aes-256-gcm'

  validates :service_name, presence: true, inclusion: { in: ServiceConnection::SERVICES }
  validates :label, presence: true

  scope :for_service, ->(name) { where(service_name: name) }
  scope :active,      -> { where(is_active: true) }

  before_save :ensure_single_active

  # そのユーザー・サービスで「いま投稿に使うアカウント」を 1 つ返す。
  # service_accounts が無ければ従来の ServiceConnection を Adapter で包んで返す（後方互換）。
  # @return [ServiceAccount, ServiceConnection, nil]
  def self.resolve(user_id:, service_name:)
    accounts = where(user_id: user_id, service_name: service_name)
    return (accounts.active.first || accounts.order(:id).first) if accounts.exists?

    ServiceConnection.find_by(user_id: user_id, service_name: service_name)
  end

  def connected?
    status == 'connected' && session_data.present?
  end

  def as_json_safe(include_password: false)
    h = {
      id: id, serviceName: service_name, label: label, handle: handle,
      status: status || 'disconnected', isActive: is_active,
      lastConnectedAt: last_connected_at&.iso8601, errorMessage: error_message,
      hasSession: session_data.present?,
    }
    h[:password] = password_field if include_password
    h
  end

  private

  # is_active を立てたら、同一ユーザー・同一サービスの他アカウントは落とす（既定は 1 つ）。
  def ensure_single_active
    return unless is_active && (will_save_change_to_is_active? || new_record?)

    ServiceAccount.where(user_id: user_id, service_name: service_name)
                  .where.not(id: id)
                  .update_all(is_active: false)
  end
end
