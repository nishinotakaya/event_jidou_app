require 'base64'

module Api
  class HostProfileController < ApplicationController
    # 外部投稿サイト（Peatix / connpass 等）の本文に埋め込まれた <img> から匿名でアクセスされるため
    # 認証をスキップする。返すのは公開して問題ない主催者アイコンのみ。
    skip_before_action :authenticate_user!, only: [:icon]

    # GET /api/host_profile/icon
    # AppSetting("host_profile_icon_data") に格納した data URL (data:image/jpeg;base64,...) を
    # デコードしてバイナリで返す。外部の投稿サイトからも直接 <img> で参照できる絶対 URL 経路。
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
