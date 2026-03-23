module Api
  class AppSettingsController < ApplicationController
    # GET /api/app_settings
    def index
      keys = params[:keys]&.split(',') || AppSetting::KNOWN_KEYS
      settings = AppSetting.bulk_get(keys)
      render json: settings
    end

    # PUT /api/app_settings
    def update
      raw = request.raw_post
      pairs = JSON.parse(raw)
      AppSetting.bulk_set(pairs)
      render json: AppSetting.bulk_get(pairs.keys)
    end
  end
end
