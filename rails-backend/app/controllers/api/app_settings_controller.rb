module Api
  class AppSettingsController < ApplicationController
    # GET /api/app_settings
    def index
      keys = params[:keys]&.split(',') || AppSetting::KNOWN_KEYS
      settings = AppSetting.bulk_get(keys)

      # host_profile_icon_data は巨大な Base64 なのでクライアントには返さず、
      # 代わりに Rails 配信の絶対 URL（host_profile_icon_public_url）を返す。
      # 外部の投稿サイト本文にも埋め込める形。
      settings = decorate_host_profile_icon(settings)
      render json: settings
    end

    # PUT /api/app_settings
    def update
      raw = request.raw_post
      pairs = JSON.parse(raw)
      AppSetting.bulk_set(pairs)
      render json: decorate_host_profile_icon(AppSetting.bulk_get(pairs.keys))
    end

    private

    # 主催者アイコンの公開 URL を host_profile_icon_public_url として返す。
    # 優先度:
    #   (1) 新方式 host_profile_icon_url (Cloudinary の絶対 URL) があればそれを使う
    #   (2) 旧方式 host_profile_icon_data (Base64) しか無ければ /api/host_profile/icon を組み立てる
    def decorate_host_profile_icon(settings)
      url_key  = AppSetting::HOST_PROFILE_ICON_URL_KEY
      data_key = AppSetting::HOST_PROFILE_ICON_KEY

      icon_url = settings.delete(url_key).to_s
      icon_data_present = settings.delete(data_key).to_s.start_with?('data:')

      if !icon_url.empty?
        settings['host_profile_icon_public_url'] = icon_url
      elsif icon_data_present
        setting = AppSetting.find_by(key: data_key)
        version = setting&.updated_at.to_i
        settings['host_profile_icon_public_url'] = "#{request.base_url}/api/host_profile/icon?v=#{version}"
      else
        # キーが要求されていた場合のみ空文字を返す
        settings['host_profile_icon_public_url'] = '' if settings.key?('host_profile_icon_public_url') || true
      end
      settings
    end
  end
end
