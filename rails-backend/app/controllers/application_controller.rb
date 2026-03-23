class ApplicationController < ActionController::API
  before_action :set_default_response_format
  before_action :authenticate_user!

  private

  def set_default_response_format
    request.format = :json
  end

  def authenticate_user!
    unless current_user
      render json: { error: 'ログインが必要です' }, status: :unauthorized
    end
  end

  def current_user
    @current_user ||= warden.user(:user)
  end

  def warden
    request.env['warden']
  end
end
