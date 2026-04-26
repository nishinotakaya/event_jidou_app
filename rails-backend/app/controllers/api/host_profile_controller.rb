require 'base64'

module Api
  class HostProfileController < ApplicationController
    # 外部投稿サイト（Peatix / connpass 等）の本文に埋め込まれた <img> から匿名でアクセスされるため
    # icon は認証をスキップする（Base64 配信の旧方式向け）。upload は認証必須。
    skip_before_action :authenticate_user!, only: [:icon]

    # POST /api/host_profile/icon
    # multipart で受け取った画像を Cloudinary に Signed Upload し、secure_url を AppSetting に保存。
    # 同じ public_id (host_profile_icon) で再 upload するので URL は固定（ただし invalidate でキャッシュ更新）。
    def upload
      file = params[:image]
      unless file.is_a?(ActionDispatch::Http::UploadedFile)
        render json: { error: '画像ファイルが必要です' }, status: :bad_request
        return
      end

      result = CloudinaryUploader.upload(file.read, folder: 'host_profile', public_id: 'icon')
      url = result['secure_url']
      AppSetting.set('host_profile_icon_url', url)
      # 旧 Base64 データは不要なので消しておく
      AppSetting.where(key: AppSetting::HOST_PROFILE_ICON_KEY).delete_all
      render json: { url: url, public_id: result['public_id'] }
    rescue CloudinaryUploader::ConfigurationError => e
      render json: { error: "Cloudinary 設定エラー: #{e.message}" }, status: :service_unavailable
    rescue CloudinaryUploader::UploadError => e
      render json: { error: e.message }, status: :bad_gateway
    end

    # GET /api/host_profile/icon  （旧 Base64 配信、後方互換のため残す）
    # 新方式では Cloudinary URL が AppSetting('host_profile_icon_url') に直接入るため
    # このエンドポイントを経由せず <img src> で直接 Cloudinary を参照する。
    def icon
      setting = AppSetting.find_by(key: AppSetting::HOST_PROFILE_ICON_KEY)
      data_url = setting&.value.to_s

      match = data_url.match(%r{\Adata:(?<mime>[^;]+);base64,(?<b64>.+)\z}m)
      unless match
        head :not_found
        return
      end

      begin
        binary = Base64.strict_decode64(match[:b64])
      rescue ArgumentError
        head :not_found
        return
      end

      response.set_header('Cache-Control', 'public, max-age=60, must-revalidate')
      response.set_header('ETag', %("#{setting.updated_at.to_i}"))
      send_data binary, type: match[:mime], disposition: 'inline'
    end
  end
end
