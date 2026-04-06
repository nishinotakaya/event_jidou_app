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
          passcode: s.passcode.to_s.match?(/\A\d{4,10}\z/) ? s.passcode : '',
          updatedAt: s.updated_at.strftime("%Y-%m-%d %H:%M"),
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
      raw_title  = params[:title].to_s.presence || 'ミーティング'
      start_date = params[:startDate].to_s
      start_time = params[:startTime].to_s.presence || '10:00'
      duration   = (params[:duration] || 120).to_i

      date_label = begin
        d = Date.parse(start_date)
        "#{d.month}/#{d.day}"
      rescue
        ''
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
          passcode: setting.passcode,
        },
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

    private

    def zoom_params
      params.permit(:label, :title, :zoom_url, :meeting_id, :passcode)
    end
  end
end
