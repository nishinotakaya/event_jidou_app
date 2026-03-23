Rails.application.routes.draw do
  devise_for :users, path: '', controllers: {
    omniauth_callbacks: 'users/omniauth_callbacks',
    sessions: 'users/sessions',
  }
  get "up" => "rails/health#show", as: :rails_health_check

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"

  namespace :api do
    # テキスト CRUD
    get    "texts/:type",     to: "texts#index"
    post   "texts/:type",     to: "texts#create"
    put    "texts/:type/:id", to: "texts#update"
    delete "texts/:type/:id", to: "texts#destroy"

    # フォルダ CRUD
    get    "folders/:type", to: "folders#index"
    post   "folders/:type", to: "folders#create"
    put    "folders/:type", to: "folders#update"
    delete "folders/:type", to: "folders#destroy"

    # Zoom設定
    get    "zoom_settings",     to: "zoom_settings#index"
    post   "zoom_settings",     to: "zoom_settings#create"
    put    "zoom_settings/:id", to: "zoom_settings#update"
    delete "zoom_settings/:id", to: "zoom_settings#destroy"

    # アプリ設定（KVS）
    get "app_settings", to: "app_settings#index"
    put "app_settings", to: "app_settings#update"

    # サービス接続管理
    get    "service_connections",                    to: "service_connections#index"
    post   "service_connections",                    to: "service_connections#create"
    put    "service_connections/:id",                to: "service_connections#update"
    delete "service_connections/:id",                to: "service_connections#destroy"
    post   "service_connections/:id/test",           to: "service_connections#test_connection"
    post   "service_connections/test_new",           to: "service_connections#test_new"
    post   "service_connections/migrate_from_env",   to: "service_connections#migrate_from_env"

    # 現在のユーザー情報
    get "current_user", to: "sessions#current_user"
    post "login", to: "sessions#login"
    delete "logout", to: "sessions#logout"
    get "csrf_token", to: "sessions#csrf_token"

    # Zoomミーティング自動作成
    post "zoom/create_meeting", to: "zoom_settings#create_meeting"

    # 投稿（ActionCable + Sidekiq バックグラウンドジョブ）
    post "post", to: "post#create"

    # AI
    post "ai/correct",        to: "ai#correct"
    post "ai/generate",       to: "ai#generate"
    post "ai/align-datetime", to: "ai#align_datetime"
    post "ai/agent",          to: "ai#agent"
  end
end
