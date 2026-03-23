module Api
  class ServiceConnectionsController < ApplicationController
    # GET /api/service_connections
    def index
      connections = ServiceConnection.all.map(&:as_json_safe)
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
      conn.status = 'disconnected'
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
      TestConnectionJob.perform_later(conn.id)
      render json: { message: '接続テストを開始しました', status: conn.status }
    end

    # POST /api/service_connections/test_new
    def test_new
      service_name = params[:service_name]
      email = params[:email]
      password = params[:password]

      unless ServiceConnection::SERVICES.include?(service_name)
        return render json: { error: '不明なサービスです' }, status: :unprocessable_entity
      end

      # 保存してからテスト
      conn = ServiceConnection.find_or_initialize_by(service_name: service_name)
      conn.email = email
      conn.password_field = password
      conn.status = 'testing'
      conn.save!

      TestConnectionJob.perform_later(conn.id)
      render json: conn.as_json_safe.merge(message: '接続テストを開始しました')
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
  end
end
