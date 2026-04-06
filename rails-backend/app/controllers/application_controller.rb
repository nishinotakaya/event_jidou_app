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

  def authorize_admin!
    render json: { error: '管理者権限が必要です' }, status: :forbidden unless current_user&.admin?
  end

  def authorize_editor!
    render json: { error: '編集権限が必要です' }, status: :forbidden unless current_user&.can_edit?
  end

  def current_user
    @current_user ||= warden.user(:user)
  end

  def warden
    request.env['warden']
  end
end
