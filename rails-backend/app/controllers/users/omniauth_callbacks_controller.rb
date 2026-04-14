class Users::OmniauthCallbacksController < ActionController::Base
  include ActionController::Cookies

  def google_oauth2
    auth = request.env['omniauth.auth']
    Rails.logger.info "[OmniAuth] credentials: token=#{auth.credentials&.token.present?} refresh=#{auth.credentials&.refresh_token.present?} expires=#{auth.credentials&.expires_at}"
    @user = User.from_omniauth(auth)

    if @user.persisted?
      request.env['warden'].set_user(@user, scope: :user)
      # ワンタイムトークンを生成してフロントエンドに渡す
      token = SecureRandom.hex(32)
      Rails.cache.write("login_token:#{token}", @user.id, expires_in: 60.seconds)
      redirect_to "#{frontend_url}/?login=success&token=#{token}", allow_other_host: true
    else
      redirect_to "#{frontend_url}/?login=failed", allow_other_host: true
    end
  end

  def failure
    redirect_to "#{frontend_url}/?login=failed&reason=#{params[:message]}", allow_other_host: true
  end

  private

  def frontend_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
  end
end
