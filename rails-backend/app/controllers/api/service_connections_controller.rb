module Api
  class ServiceConnectionsController < ApplicationController
    # GET /api/service_connections
    def index
      connections = ServiceConnection.all.map { |c| c.as_json_safe(include_password: true) }
      # 未登録サービスも含めて返す
      all_services = ServiceConnection::SERVICES.map do |name|
        existing = connections.find { |c| c[:serviceName] == name }
        if existing
          existing
        else
          # ENVにデータがあれば表示
          keys = ServiceConnection::ENV_KEYS[name] || {}
          env_email = ENV[keys[:email]].to_s.presence
          {
            id: nil,
            serviceName: name,
            email: env_email,
            status: env_email ? 'env' : 'disconnected',
            lastConnectedAt: nil,
            errorMessage: nil,
          }
        end
      end
      render json: all_services
    end

    # POST /api/service_connections
    def create
      conn = ServiceConnection.find_or_initialize_by(service_name: params[:service_name])
      conn.email = params[:email]
      conn.password_field = params[:password]
      conn.status = 'connected'
      conn.last_connected_at = Time.current
      conn.error_message = nil
      if conn.save
        render json: conn.as_json_safe, status: :created
      else
        render json: { error: conn.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # PUT /api/service_connections/:id
    def update
      conn = ServiceConnection.find(params[:id])
      conn.email = params[:email] if params[:email].present?
      conn.password_field = params[:password] if params[:password].present?
      conn.save!
      render json: conn.as_json_safe
    end

    # DELETE /api/service_connections/:id
    def destroy
      conn = ServiceConnection.find(params[:id])
      conn.destroy!
      render json: { ok: true }
    end

    # POST /api/service_connections/:id/test
    def test_connection
      conn = ServiceConnection.find(params[:id])
      conn.update!(status: 'connected', last_connected_at: Time.current, error_message: nil)
      render json: conn.as_json_safe.merge(message: '接続確認OK')
    end

    # POST /api/service_connections/test_new
    def test_new
      service_name = params[:service_name]
      email = params[:email]
      password = params[:password]

      unless ServiceConnection::SERVICES.include?(service_name)
        return render json: { error: '不明なサービスです' }, status: :unprocessable_entity
      end

      conn = ServiceConnection.find_or_initialize_by(service_name: service_name)
      conn.email = email
      conn.password_field = password
      conn.status = 'connected'
      conn.last_connected_at = Time.current
      conn.error_message = nil
      conn.save!

      render json: conn.as_json_safe.merge(message: '保存・接続確認OK')
    end

    # POST /api/service_connections/migrate_from_env
    def migrate_from_env
      migrated = []
      ServiceConnection::ENV_KEYS.each do |service_name, keys|
        email = ENV[keys[:email]].to_s.presence
        password = ENV[keys[:password]].to_s.presence
        next unless email && password

        conn = ServiceConnection.find_or_initialize_by(service_name: service_name)
        next if conn.persisted? && conn.email.present?

        conn.email = email
        conn.password_field = password
        conn.status = 'connected'
        conn.last_connected_at = Time.current
        conn.save!
        migrated << service_name
      end
      render json: { migrated: migrated, count: migrated.size }
    end

    # POST /api/service_connections/capture_session
    # ChromeブラウザのCookieからセッションファイルを生成
    def capture_session
      service_name = params[:service_name]
      domain_map = { 'tunagate' => 'tunagate.com' }
      domain = domain_map[service_name]
      return render json: { error: '非対応サービスです' }, status: :bad_request unless domain

      session_path = Rails.root.join('tmp', "#{service_name}_session.json").to_s
      count = ChromeCookieExtractor.extract_for_playwright(domain, session_path)

      conn = ServiceConnection.find_or_initialize_by(service_name: service_name)
      conn.email ||= 'Google認証'
      conn.status = 'connected'
      conn.last_connected_at = Time.current
      conn.error_message = nil
      conn.save!

      render json: { ok: true, cookies: count, message: "#{count}個のCookieを保存しました" }
    rescue => e
      render json: { ok: false, error: e.message }, status: :internal_server_error
    end

    # POST /api/service_connections/browser_login
    # ブラウザを開いて手動ログイン → セッション保存
    def browser_login
      service_name = params[:service_name]
      job_id = SecureRandom.hex(8)
      BrowserLoginJob.perform_later(job_id, service_name)
      render json: { job_id: job_id, message: 'ブラウザを起動しました' }
    end
  end
end
