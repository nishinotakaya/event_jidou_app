class ServiceConnection < ApplicationRecord
  SERVICES = %w[
    kokuchpro connpass peatix techplay zoom tunagate doorkeeper
    street_academy eventregist passmarket luma seminar_biz jimoty gmail
    twitter instagram facebook threads onclass github
  ].freeze
  # コメントアウト: lme, seminars, everevo

  # トークン型サービス（email/passwordではなくトークン1つ）
  TOKEN_SERVICES = %w[github].freeze

  ENV_KEYS = {
    'kokuchpro'       => { email: 'CONPASS__KOKUCIZE_MAIL', password: 'CONPASS_KOKUCIZE_PASSWORD' },
    'connpass'        => { email: 'CONPASS__KOKUCIZE_MAIL', password: 'CONPASS_KOKUCIZE_PASSWORD' },
    'peatix'          => { email: 'PEATIX_EMAIL', password: 'PEATIX_PASSWORD' },
    'techplay'        => { email: 'TECHPLAY_EMAIL', password: 'TECHPLAY_PASSWORD' },
    'zoom'            => { email: 'ZOOM_EMAIL', password: 'ZOOM_PASSWORD' },
    'lme'             => { email: 'LME_EMAIL', password: 'LME_PASSWORD' },
    'tunagate'        => { email: 'GOOGLE_EMAIL', password: 'GOOGLE_PASSWORD' },
    'doorkeeper'      => { email: 'DOORKEEPER_EMAIL', password: 'DOORKEEPER_PASSWORD' },
    'seminars'        => { email: 'SEMINARS_EMAIL', password: 'SEMINARS_PASSWORD' },
    'street_academy'  => { email: 'STREET_ACADEMY_EMAIL', password: 'STREET_ACADEMY_PASSWORD' },
    'eventregist'     => { email: 'EVENTREGIST_EMAIL', password: 'EVENTREGIST_PASSWORD' },
    'passmarket'      => { email: 'GOOGLE_EMAIL', password: 'GOOGLE_PASSWORD' },
    'everevo'         => { email: 'EVEREVO_EMAIL', password: 'EVEREVO_PASSWORD' },
    'luma'            => { email: 'GOOGLE_EMAIL', password: 'GOOGLE_PASSWORD' },
    'seminar_biz'     => { email: 'SEMINAR_BIZ_EMAIL', password: 'SEMINAR_BIZ_PASSWORD' },
    'jimoty'          => { email: 'JIMOTY_EMAIL', password: 'JIMOTY_PASSWORD' },
    'gmail'           => { email: 'GOOGLE_EMAIL', password: nil },
    'twitter'         => { email: 'TWITTER_EMAIL', password: 'TWITTER_PASSWORD' },
    'instagram'       => { email: 'INSTAGRAM_EMAIL', password: 'INSTAGRAM_PASSWORD' },
    'facebook'        => { email: 'FACEBOOK_EMAIL', password: 'FACEBOOK_PASSWORD' },
    'threads'         => { email: 'INSTAGRAM_EMAIL', password: 'INSTAGRAM_PASSWORD' },
    'onclass'         => { email: 'ONCLASS_EMAIL', password: 'ONCLASS_PASSWORD' },
    'github'          => { email: nil, password: 'GITHUB_TOKEN' },
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
    if TOKEN_SERVICES.include?(service_name)
      # トークン型: password_fieldにトークンを保存
      token = conn&.password_field.presence || ENV[ENV_KEYS.dig(service_name, :password)].to_s
      { token: token, email: nil, password: token }
    elsif conn&.email.present?
      { email: conn.email, password: conn.password_field }
    else
      keys = ENV_KEYS[service_name] || {}
      { email: ENV[keys[:email]].to_s, password: ENV[keys[:password]].to_s }
    end
  end

  def as_json_safe(include_password: false)
    h = {
      id: id,
      serviceName: service_name,
      email: email,
      status: status || 'disconnected',
      lastConnectedAt: last_connected_at&.iso8601,
      errorMessage: error_message,
    }
    h[:password] = password_field if include_password
    h
  end

  private

  def set_default_status
    self.status ||= 'disconnected'
  end
end
