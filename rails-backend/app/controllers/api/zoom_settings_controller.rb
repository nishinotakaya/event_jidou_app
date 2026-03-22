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
    # Enqueues ZoomJob → ActionCable でリアルタイムログ配信
    def create_meeting
      job_id = SecureRandom.hex(8)

      payload = {
        'title'     => params[:title].to_s,
        'startDate' => params[:startDate].to_s,
        'startTime' => params[:startTime].to_s,
        'duration'  => params[:duration] || 120,
      }

      ZoomJob.perform_later(job_id, payload)
      render json: { job_id: job_id }
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
