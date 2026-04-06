class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  ROLES = %w[admin editor viewer].freeze
  validates :role, inclusion: { in: ROLES }

  def admin?  = role == 'admin'
  def editor? = role == 'editor'
  def viewer? = role == 'viewer'
  def can_edit?  = admin? || editor?
  def can_post?  = admin? || editor?

  has_many :items, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :service_connections, dependent: :destroy

  def self.from_omniauth(auth)
    # まずprovider+uidで検索
    user = find_by(provider: auth.provider, uid: auth.uid)
    if user
      # トークンを毎回更新
      user.update!(
        google_access_token: auth.credentials&.token,
        google_refresh_token: auth.credentials&.refresh_token || user.google_refresh_token,
        google_token_expires_at: auth.credentials&.expires_at ? Time.at(auth.credentials.expires_at) : user.google_token_expires_at,
        avatar_url: auth.info.image || user.avatar_url,
      )
      return user
    end

    # 同じメールアドレスのユーザーがいれば紐付け
    user = find_by(email: auth.info.email)
    if user
      user.update!(
        provider: auth.provider,
        uid: auth.uid,
        name: auth.info.name || user.name,
        avatar_url: auth.info.image,
        google_access_token: auth.credentials&.token,
        google_refresh_token: auth.credentials&.refresh_token || user.google_refresh_token,
        google_token_expires_at: auth.credentials&.expires_at ? Time.at(auth.credentials.expires_at) : nil,
      )
      return user
    end

    # 新規作成
    create!(
      email: auth.info.email,
      password: Devise.friendly_token[0, 20],
      name: auth.info.name,
      avatar_url: auth.info.image,
      provider: auth.provider,
      uid: auth.uid,
      google_access_token: auth.credentials&.token,
      google_refresh_token: auth.credentials&.refresh_token,
      google_token_expires_at: auth.credentials&.expires_at ? Time.at(auth.credentials.expires_at) : nil,
    )
  end
end
