class Users::OmniauthCallbacksController < ActionController::Base
  include ActionController::Cookies

  def google_oauth2
    auth = request.env['omniauth.auth']
    @user = User.from_omniauth(auth)

    if @user.persisted?
      request.env['warden'].set_user(@user, scope: :user)
      redirect_to "#{frontend_url}/?login=success", allow_other_host: true
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
