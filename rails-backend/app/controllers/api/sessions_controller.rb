module Api
  class SessionsController < ApplicationController
    skip_before_action :authenticate_user!

    def current_user
      user = warden.user(:user)
      if user
        render json: {
          id: user.id,
          email: user.email,
          name: user.name,
          avatarUrl: user.avatar_url,
          provider: user.provider,
          role: user.role,
        }
      else
        render json: { user: nil }
      end
    end

    def login
      user = User.find_by(email: params[:email])
      if user&.valid_password?(params[:password])
        warden.set_user(user, scope: :user)
        render json: {
          id: user.id,
          email: user.email,
          name: user.name,
          avatarUrl: user.avatar_url,
          provider: user.provider,
          role: user.role,
        }
      else
        render json: { error: 'メールアドレスまたはパスワードが正しくありません' }, status: :unauthorized
      end
    end

    def logout
      warden.logout(:user)
      render json: { ok: true }
    end

    # OAuth callback で発行したワンタイムトークンを Heroku 直叩き（credentials付き）で受け取り、
    # session cookie を heroku.com ドメインに設置する。クロスドメイン構成での唯一の入口。
    def exchange
      token = params[:token].to_s
      user_id = token.present? ? Rails.cache.read("login_token:#{token}") : nil
      user = user_id && User.find_by(id: user_id)
      if user
        Rails.cache.delete("login_token:#{token}")
        warden.set_user(user, scope: :user)
        render json: {
          id: user.id,
          email: user.email,
          name: user.name,
          avatarUrl: user.avatar_url,
          provider: user.provider,
          role: user.role,
        }
      else
        render json: { error: 'invalid or expired token' }, status: :unauthorized
      end
    end

    def csrf_token
      # OmniAuth POST用のCSRFトークン生成
      session[:_csrf_token] ||= SecureRandom.base64(32)
      render json: { token: session[:_csrf_token] }
    end

    private

    def warden
      request.env['warden']
    end
  end
end
