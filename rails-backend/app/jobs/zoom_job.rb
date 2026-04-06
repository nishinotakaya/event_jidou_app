class ZoomJob < ApplicationJob
  queue_as :default

  def perform(job_id, payload)
    raw_title  = payload['title'].to_s.presence || 'ミーティング'
    start_date = payload['startDate'].to_s
    date_label = begin
      d = Date.parse(start_date)
      "#{d.month}/#{d.day}"
    rescue
      ''
    end
    title = date_label.present? ? "#{date_label} #{raw_title}" : raw_title
    start_time = payload['startTime'].to_s.presence || '10:00'
    duration   = (payload['duration'] || 120).to_i

    broadcast(job_id, type: 'log', message: 'Zoomミーティング作成を開始します...')

    log_fn = ->(msg) {
      $stdout.puts("[ZoomJob] #{msg}")
      $stdout.flush
      broadcast(job_id, type: 'log', message: msg)
    }

    service = ZoomService.new(&log_fn)
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

    broadcast(job_id, type: 'log', message: "✅ DB保存完了（ID: #{setting.id}）")
    broadcast(job_id, type: 'result', data: {
      id: setting.id,
      label: setting.label,
      title: setting.title,
      zoomUrl: setting.zoom_url,
      meetingId: setting.meeting_id,
      passcode: setting.passcode,
    })

    broadcast(job_id, type: 'done')
  rescue => e
    $stdout.puts("[ZoomJob] ERROR: #{e.message}")
    $stdout.flush
    broadcast(job_id, type: 'error', message: e.message)
    broadcast(job_id, type: 'done')
  end

  private

  def broadcast(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end
end
