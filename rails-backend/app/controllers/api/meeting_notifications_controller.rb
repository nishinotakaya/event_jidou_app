module Api
  # 定例ミーティング通知設定の管理（CRUD）とテスト送信。
  class MeetingNotificationsController < ApplicationController
    def index
      render json: MeetingNotification.order(:weekday, :notify_time).map { |m| serialize(m) }
    end

    def create
      notification = MeetingNotification.new(notification_params)
      if notification.save
        render json: serialize(notification), status: :created
      else
        render json: { error: notification.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    def update
      notification = MeetingNotification.find(params[:id])
      if notification.update(notification_params)
        render json: serialize(notification)
      else
        render json: { error: notification.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    def destroy
      MeetingNotification.find(params[:id]).destroy!
      render json: { ok: true }
    end

    # POST /api/meeting_notifications/:id/send_now
    # 今すぐ1件テスト送信（オンクラスへ実投稿する）
    def send_now
      notification = MeetingNotification.find(params[:id])
      text = MeetingNotifyJob.deliver(notification)
      render json: { ok: true, text: text }
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # GET /api/meeting_notifications/:id/preview
    # 送信せずに本文プレビューだけ返す（AI挨拶込み）
    def preview
      notification = MeetingNotification.find(params[:id])
      render json: { text: MeetingNotificationComposer.new(notification).call }
    end

    private

    def notification_params
      params.require(:meetingNotification).permit(
        :name, :onclassChannel, :zoomUrl, :meetingId, :passcode,
        :weekday, :startTime, :endTime, :notifyTime, :enabled, :messageTemplate
      ).transform_keys do |key|
        {
          "onclassChannel" => "onclass_channel", "zoomUrl" => "zoom_url",
          "meetingId" => "meeting_id", "startTime" => "start_time",
          "endTime" => "end_time", "notifyTime" => "notify_time",
          "messageTemplate" => "message_template"
        }.fetch(key, key)
      end
    end

    def serialize(m)
      {
        id: m.id,
        name: m.name,
        onclassChannel: m.onclass_channel,
        zoomUrl: m.zoom_url,
        meetingId: m.meeting_id,
        passcode: m.passcode,
        weekday: m.weekday,
        startTime: m.start_time,
        endTime: m.end_time,
        notifyTime: m.notify_time,
        enabled: m.enabled,
        messageTemplate: m.message_template,
        defaultTemplate: MeetingNotification::DEFAULT_TEMPLATE,
        lastSentOn: m.last_sent_on&.iso8601
      }
    end
  end
end
