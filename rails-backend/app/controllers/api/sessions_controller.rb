module Api
  class SessionsController < ApplicationController
    def current_user
      user = warden.user(:user)
      if user
        render json: {
          id: user.id,
          email: user.email,
          name: user.name,
          avatarUrl: user.avatar_url,
          provider: user.provider,
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
        }
      else
        render json: { error: 'メールアドレスまたはパスワードが正しくありません' }, status: :unauthorized
      end
    end

    def logout
      warden.logout(:user)
      render json: { ok: true }
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
