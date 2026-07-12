module Api
  class ZoomSettingsController < ApplicationController
    # GET /api/zoom_settings
    def index
      settings = ZoomSetting.order(updated_at: :desc)
      render json: settings.map { |s|
        {
          id: s.id,
          label: s.label,
          title: s.title,
          zoomUrl: s.zoom_url,
          meetingId: s.meeting_id,
          passcode: s.passcode.to_s.match?(/\A\d{4,10}\z/) ? s.passcode : "",
          updatedAt: s.updated_at.strftime("%Y-%m-%d %H:%M")
        }
      }
    end

    # POST /api/zoom_settings
    def create
      setting = ZoomSetting.new(zoom_params)
      if setting.save
        render json: { id: setting.id, message: "保存しました" }, status: :created
      else
        render json: { error: setting.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    # PUT /api/zoom_settings/:id
    def update
      setting = ZoomSetting.find(params[:id])
      if setting.update(zoom_params)
        render json: { id: setting.id, message: "更新しました" }
      else
        render json: { error: setting.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    # POST /api/zoom/create_meeting
    # Zoom OAuth API で同期的にミーティング作成（0.5秒で完了）
    def create_meeting
      raw_title  = params[:title].to_s.presence || "ミーティング"
      start_date = params[:startDate].to_s
      start_time = params[:startTime].to_s.presence || "10:00"
      duration   = (params[:duration] || 120).to_i

      date_label = begin
        d = Date.parse(start_date)
        "#{d.month}/#{d.day}"
      rescue
        ""
      end
      title = date_label.present? ? "#{date_label} #{raw_title}" : raw_title

      service = ZoomService.new
      result = service.create_meeting(
        title: title,
        start_date: start_date,
        start_time: start_time,
        duration_minutes: duration,
      )

      setting = ZoomSetting.create!(
        label: title,
        title: title,
        zoom_url: result[:zoom_url],
        meeting_id: result[:meeting_id],
        passcode: result[:passcode],
      )

      render json: {
        ok: true,
        data: {
          id: setting.id,
          label: setting.label,
          title: setting.title,
          zoomUrl: setting.zoom_url,
          meetingId: setting.meeting_id,
          passcode: setting.passcode
        }
      }
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # DELETE /api/zoom_settings/:id
    def destroy
      setting = ZoomSetting.find(params[:id])
      setting.destroy
      render json: { message: "削除しました" }
    end

    # POST /api/zoom/update_meeting
    # body: { zoomUrl または meetingId, title }
    # Zoom API でミーティングのタイトル(topic)を変更。保存済みZoom設定があれば同期する。
    def update_meeting
      meeting_ref = params[:zoomUrl].presence || params[:meetingId].presence
      title = params[:title].to_s.strip
      return render json: { ok: false, error: "Zoom URL とタイトルが必要です" }, status: :unprocessable_entity if meeting_ref.blank? || title.blank?

      ZoomService.new.update_meeting(meeting_id: meeting_ref, title: title)
      sync_zoom_setting_title(meeting_ref, title)
      render json: { ok: true, title: title }
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /api/zoom/delete_meeting
    # body: { zoomUrl または meetingId }
    # Zoom API でミーティングを削除。保存済みZoom設定も併せて削除する。
    def delete_meeting
      meeting_ref = params[:zoomUrl].presence || params[:meetingId].presence
      return render json: { ok: false, error: "Zoom URL が必要です" }, status: :unprocessable_entity if meeting_ref.blank?

      ZoomService.new.delete_meeting(meeting_id: meeting_ref)
      delete_zoom_setting(meeting_ref)
      render json: { ok: true }
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    # 数字のみのミーティングIDで保存済みZoom設定を探す
    def find_settings_by_meeting(meeting_ref)
      digits = ZoomService.extract_meeting_id(meeting_ref)
      return ZoomSetting.none if digits.blank?

      ZoomSetting.select { |s| s.meeting_id.to_s.gsub(/\D/, "") == digits || s.zoom_url.to_s.include?(digits) }
    end

    def sync_zoom_setting_title(meeting_ref, title)
      find_settings_by_meeting(meeting_ref).each { |s| s.update(label: title, title: title) }
    end

    def delete_zoom_setting(meeting_ref)
      find_settings_by_meeting(meeting_ref).each(&:destroy)
    end

    def zoom_params
      params.permit(:label, :title, :zoom_url, :meeting_id, :passcode)
    end
  end
end
