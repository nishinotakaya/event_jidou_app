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
    post   "service_connections/browser_login",      to: "service_connections#browser_login"
    post   "service_connections/capture_session",    to: "service_connections#capture_session"

    # 現在のユーザー情報
    get "current_user", to: "sessions#current_user"
    post "login", to: "sessions#login"
    delete "logout", to: "sessions#logout"
    get "csrf_token", to: "sessions#csrf_token"

    # Zoomミーティング自動作成
    post "zoom/create_meeting", to: "zoom_settings#create_meeting"

    # 投稿履歴
    get   "posting_histories",                      to: "posting_histories#index"
    get   "posting_histories/latest",               to: "posting_histories#latest"
    post  "posting_histories/check_registrations",  to: "posting_histories#check_registrations"
    post  "posting_histories/sync",                 to: "posting_histories#sync"
    post  "posting_histories/check_participants",   to: "posting_histories#check_participants"
    patch "posting_histories/:id/mark_success",     to: "posting_histories#mark_success"
    patch "posting_histories/:id/update_url",       to: "posting_histories#update_url"
    post  "posting_histories/create_manual",         to: "posting_histories#create_manual"

    # 参加者
    get   "participants",          to: "participants#index"
    post  "participants/sync",     to: "participants#sync"
    post  "posting_histories/bulk_mark_success",    to: "posting_histories#bulk_mark_success"

    # 投稿（ActionCable + Sidekiq バックグラウンドジョブ）
    post "post", to: "post#create"
    delete "post/:item_id/remote", to: "post#delete_remote"
    post   "post/:item_id/cancel", to: "post#cancel_remote"
    post   "post/:item_id/publish_all", to: "post#publish_all"
    post   "post/:item_id/retry_errors", to: "post#retry_errors"

    # オンクラス
    get    "onclass/students", to: "onclass#students"
    get    "onclass/students_list", to: "onclass#students_list"
    delete "onclass/students/:id", to: "onclass#destroy_student"
    post   "onclass/sync", to: "onclass#sync"
    post   "onclass/sync_sidekiq", to: "onclass#sync_sidekiq"
    post   "onclass/upload_image", to: "onclass#upload_image"

    # GitHubレビュー
    get    "github_reviews",                     to: "github_reviews#index"
    get    "github_reviews/:id",                 to: "github_reviews#show"
    put    "github_reviews/:id",                 to: "github_reviews#update"
    post   "github_reviews/:id/approve",         to: "github_reviews#approve"
    post   "github_reviews/:id/post_to_github",  to: "github_reviews#post_to_github"
    post   "github_reviews/:id/re_review",       to: "github_reviews#re_review"
    post   "github_reviews/:id/open_local",      to: "github_reviews#open_local"
    post   "github_reviews/scan",                to: "github_reviews#scan"

    # 日時重複チェック
    post "check_duplicate_event", to: "texts#check_duplicate"

    # 画像アップロード（汎用）
    post "upload_image", to: "images#upload"

    # 生成/アップロード画像ライブラリ（DB保存）
    get    "generated_images",     to: "generated_images#index"
    get    "generated_images/:id", to: "generated_images#show", as: :generated_image
    post   "generated_images",     to: "generated_images#create"
    delete "generated_images/:id", to: "generated_images#destroy"

    # Googleカレンダー
    get  "calendar/events",   to: "calendar#events"
    post "calendar/events",   to: "calendar#create_event"
    put    "calendar/events/:event_id", to: "calendar#update_event"
    delete "calendar/events/:event_id", to: "calendar#delete_event"

    # ユーザー管理（admin専用）
    namespace :admin do
      get    "users",          to: "users#index"
      post   "users/invite",   to: "users#invite"
      put    "users/:id",      to: "users#update"
      delete "users/:id",      to: "users#destroy"
    end

    # AI
    post "ai/correct",        to: "ai#correct"
    post "ai/generate",       to: "ai#generate"
    post "ai/align-datetime", to: "ai#align_datetime"
    post "ai/agent",          to: "ai#agent"
  end
end
