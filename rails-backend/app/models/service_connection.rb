class ServiceConnection < ApplicationRecord
  SERVICES = %w[kokuchpro connpass peatix techplay zoom lme].freeze

  ENV_KEYS = {
    'kokuchpro' => { email: 'CONPASS__KOKUCIZE_MAIL', password: 'CONPASS_KOKUCIZE_PASSWORD' },
    'connpass'  => { email: 'CONPASS__KOKUCIZE_MAIL', password: 'CONPASS_KOKUCIZE_PASSWORD' },
    'peatix'    => { email: 'PEATIX_EMAIL', password: 'PEATIX_PASSWORD' },
    'techplay'  => { email: 'TECHPLAY_EMAIL', password: 'TECHPLAY_PASSWORD' },
    'zoom'      => { email: 'ZOOM_EMAIL', password: 'ZOOM_PASSWORD' },
    'lme'       => { email: 'LME_EMAIL', password: 'LME_PASSWORD' },
  }.freeze

  belongs_to :user, optional: true

  attr_encrypted :password_field,
                 key: ->(_) { ENV.fetch('ENCRYPTION_KEY', '0' * 64)[0, 32] },
                 algorithm: 'aes-256-gcm'

  validates :service_name, presence: true, inclusion: { in: SERVICES }
  validates :service_name, uniqueness: { scope: :user_id }

  before_save :set_default_status

  scope :connected, -> { where(status: 'connected') }

  def self.credentials_for(service_name)
    conn = find_by(service_name: service_name)
    if conn&.email.present?
      { email: conn.email, password: conn.password_field }
    else
      keys = ENV_KEYS[service_name] || {}
      { email: ENV[keys[:email]].to_s, password: ENV[keys[:password]].to_s }
    end
  end

  def as_json_safe
    {
      id: id,
      serviceName: service_name,
      email: email,
      status: status || 'disconnected',
      lastConnectedAt: last_connected_at&.iso8601,
      errorMessage: error_message,
    }
  end

  private

  def set_default_status
    self.status ||= 'disconnected'
  end
end
