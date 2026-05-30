module Api
  # 1 サービス複数アカウント（X サブ垢・IG 複数運用）の管理 API。
  # 既存の単一接続（ServiceConnection）はそのまま残し、こちらは追加レイヤー。
  class ServiceAccountsController < ApplicationController
    before_action :authenticate_user!

    # GET /api/service_accounts?service=x
    def index
      scope = current_user.service_accounts
      scope = scope.for_service(params[:service]) if params[:service].present?
      render json: { accounts: scope.order(:service_name, :id).map(&:as_json_safe) }
    end

    # POST /api/service_accounts
    # body: { service_name, label, handle?, auth_token?, ct0?, email?, password?, is_active? }
    def create
      account = current_user.service_accounts.new(
        service_name: params[:service_name],
        label:        params[:label].presence || 'アカウント',
        handle:       params[:handle],
        is_active:    ActiveModel::Type::Boolean.new.cast(params[:is_active]),
      )
      apply_credentials(account)

      if account.save
        render json: { account: account.as_json_safe }, status: :created
      else
        render json: { error: account.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # PUT /api/service_accounts/:id
    def update
      account = current_user.service_accounts.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless account

      account.label     = params[:label]  if params.key?(:label)
      account.handle    = params[:handle] if params.key?(:handle)
      account.is_active = ActiveModel::Type::Boolean.new.cast(params[:is_active]) if params.key?(:is_active)
      apply_credentials(account)

      if account.save
        render json: { account: account.as_json_safe }
      else
        render json: { error: account.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # DELETE /api/service_accounts/:id
    def destroy
      account = current_user.service_accounts.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless account
      account.destroy!
      render json: { ok: true }
    end

    # POST /api/service_accounts/:id/activate → そのサービスの既定アカウントに切替
    def activate
      account = current_user.service_accounts.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless account
      account.update!(is_active: true)
      render json: { ok: true, account: account.as_json_safe }
    end

    # POST /api/service_accounts/:id/test → 接続確認（現状 X のみ verify 実装）
    def test
      account = current_user.service_accounts.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless account

      if account.service_name == 'x' && account.session_data.present?
        result = X::Client.new(account.session_data).verify
        if result[:ok]
          account.update(status: 'connected', last_connected_at: Time.current, error_message: nil, handle: result[:screen_name])
          render json: { ok: true, screen_name: result[:screen_name] }
        else
          account.update(status: 'error', error_message: (result[:error] || result[:status]).to_s[0, 500])
          render json: { ok: false, error: result[:error] || result[:status] }
        end
      else
        render json: { ok: false, error: 'このサービスの接続確認は未対応です' }
      end
    end

    private

    # トークン型（X: auth_token/ct0）と ID/PW 型の両方を受け付ける。
    def apply_credentials(account)
      if params[:auth_token].present? || params[:ct0].present?
        account.session_data = { auth_token: params[:auth_token].to_s.strip, ct0: params[:ct0].to_s.strip }.to_json
        account.status = 'connected'
        account.last_connected_at = Time.current
      end
      account.email = params[:email] if params.key?(:email)
      account.password_field = params[:password] if params[:password].present?
    end
  end
end
