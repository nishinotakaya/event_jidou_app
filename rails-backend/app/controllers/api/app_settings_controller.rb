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

    def decorate_host_profile_icon(settings)
      icon_key = AppSetting::HOST_PROFILE_ICON_KEY
      return settings unless settings.key?(icon_key)

      icon_data = settings.delete(icon_key)
      if icon_data.to_s.start_with?('data:')
        setting = AppSetting.find_by(key: icon_key)
        version = setting&.updated_at.to_i
        settings['host_profile_icon_public_url'] =
          "#{request.base_url}/api/host_profile/icon?v=#{version}"
      else
        settings['host_profile_icon_public_url'] = ''
      end
      settings
    end
  end
end
