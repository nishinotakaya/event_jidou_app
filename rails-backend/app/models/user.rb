class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  has_many :service_connections, dependent: :destroy

  def self.from_omniauth(auth)
    # まずprovider+uidで検索
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    # 同じメールアドレスのユーザーがいれば紐付け
    user = find_by(email: auth.info.email)
    if user
      user.update!(
        provider: auth.provider,
        uid: auth.uid,
        name: auth.info.name || user.name,
        avatar_url: auth.info.image,
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
    )
  end
end
