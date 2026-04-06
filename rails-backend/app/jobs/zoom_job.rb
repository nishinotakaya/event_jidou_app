require 'playwright'
require 'shellwords'

class ZoomJob < ApplicationJob
  queue_as :default

  STORAGE_STATE_PATH = Rails.root.join('tmp', 'zoom_session.json').to_s

  def perform(job_id, payload)
    raw_title  = payload['title'].to_s.presence || 'ミーティング'
    start_date = payload['startDate'].to_s
    # タイトルに開催日を付与
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

    playwright_path = find_playwright_path
    result = nil

    Playwright.create(playwright_cli_executable_path: playwright_path) do |pw|
      # セッション復元でバックグラウンド実行
      browser = pw.chromium.launch(
        headless: true,
        args: [
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-blink-features=AutomationControlled',
          '--disable-dev-shm-usage',
        ],
      )

      # DBからセッション復元
      context_opts = {
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      }
      zoom_conn = ServiceConnection.find_by(service_name: 'zoom')
      if zoom_conn&.session_data.present?
        begin
          context_opts[:storageState] = JSON.parse(zoom_conn.session_data)
          broadcast(job_id, type: 'log', message: 'DBから保存済みセッションを復元中...')
        rescue JSON::ParserError
          broadcast(job_id, type: 'log', message: 'セッションデータ破損 - 新規ログインします')
        end
      end

      context = browser.new_context(**context_opts)
      page = context.new_page
      # ヘッドレス検出回避
      page.add_init_script(script: <<~JS)
        Object.defineProperty(navigator, 'webdriver', { get: () => false });
        Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
        Object.defineProperty(navigator, 'languages', { get: () => ['ja-JP', 'ja', 'en-US', 'en'] });
        window.chrome = { runtime: {} };
      JS

      log_fn = ->(msg) {
        $stdout.puts("[ZoomJob] #{msg}")
        $stdout.flush
        broadcast(job_id, type: 'log', message: msg)
      }

      service = ZoomService.new(&log_fn)
      result = service.create_meeting(
        page,
        title: title,
        start_date: start_date,
        start_time: start_time,
        duration_minutes: duration,
      )

      # セッションをDBに保存
      begin
        state = context.storage_state
        zoom_conn&.update!(session_data: state.to_json) if zoom_conn
        broadcast(job_id, type: 'log', message: 'セッションをDBに保存しました')
      rescue => e
        broadcast(job_id, type: 'log', message: "セッション保存失敗: #{e.message}")
      end

      context.close rescue nil
      browser.close rescue nil
    end

    if result
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
    end

    broadcast(job_id, type: 'done')
  rescue => e
    $stdout.puts("[ZoomJob] ERROR: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    $stdout.flush
    broadcast(job_id, type: 'error', message: e.message)
    broadcast(job_id, type: 'done')
  end

  private

  def broadcast(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end

  def find_playwright_path
    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    if File.exist?(local)
      wrapper = '/tmp/playwright-runner.sh'
      unless File.exist?(wrapper)
        File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
        File.chmod(0o755, wrapper)
      end
      return wrapper
    end
    npx = `which npx`.strip
    npx.present? ? "#{npx} playwright" : 'npx playwright'
  end
end
