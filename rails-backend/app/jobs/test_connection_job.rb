require 'playwright'
require 'shellwords'

class TestConnectionJob < ApplicationJob
  queue_as :default

  SERVICE_CLASS = {
    'kokuchpro'       => 'Posting::KokuchproService',
    'connpass'        => 'Posting::ConnpassService',
    'peatix'          => 'Posting::PeatixService',
    'techplay'        => 'Posting::TechplayService',
    'tunagate'        => 'Posting::TunagateService',
    'doorkeeper'      => 'Posting::DoorkeeperService',
    'street_academy'  => 'Posting::StreetAcademyService',
    'eventregist'     => 'Posting::EventregistService',
    'luma'            => 'Posting::LumaService',
    'seminar_biz'     => 'Posting::SeminarBizService',
    'jimoty'          => 'Posting::JimotyService',
    'seminars'        => 'Posting::SeminarsService',
  }.freeze

  LABEL = {
    'kokuchpro' => 'こくチーズ', 'connpass' => 'connpass', 'peatix' => 'Peatix',
    'techplay' => 'TechPlay', 'tunagate' => 'つなゲート', 'doorkeeper' => 'Doorkeeper',
    'street_academy' => 'ストアカ', 'eventregist' => 'EventRegist', 'luma' => 'Luma',
    'seminar_biz' => 'セミナーBiZ', 'jimoty' => 'ジモティー', 'seminars' => 'セミナーズ',
  }.freeze

  # 新API: job_id + service_name
  # 旧API互換: connection_id のみ
  def perform(*args)
    if args.length == 2
      perform_with_job_id(args[0], args[1])
    else
      perform_legacy(args[0])
    end
  end

  private

  def perform_with_job_id(job_id, service_name)
    label = LABEL[service_name] || service_name
    conn = ServiceConnection.find_by(service_name: service_name)

    klass_name = SERVICE_CLASS[service_name]
    unless klass_name
      # Zoom等のPlaywright不要サービス
      conn&.update!(status: 'connected', last_connected_at: Time.current, error_message: nil)
      broadcast_cable(job_id, type: 'done')
      broadcast_status(conn)
      return
    end

    conn&.update!(status: 'testing', error_message: nil)
    broadcast_status(conn)

    pw_path = find_playwright_path
    Playwright.create(playwright_cli_executable_path: pw_path) do |pw|
      browser = pw.chromium.launch(
        headless: true,
        args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu', '--single-process']
      )
      ctx_opts = {
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/145.0.0.0 Safari/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      }
      if conn&.session_data.present?
        ctx_opts[:storageState] = JSON.parse(conn.session_data) rescue nil
      end

      ctx = browser.new_context(**ctx_opts.compact)
      page = ctx.new_page

      begin
        svc = klass_name.constantize.new
        svc.instance_variable_set(:@log_callback, ->(msg) {
          broadcast_cable(job_id, type: 'log', message: msg)
        })

        if service_name == 'peatix'
          svc.send(:login_and_get_bearer, page)
        else
          svc.send(:ensure_login, page)
        end

        # セッション保存
        sd = JSON.generate(ctx.storage_state) rescue nil
        conn&.update!(
          session_data: sd,
          status: 'connected',
          last_connected_at: Time.current,
          error_message: nil,
        )
        broadcast_cable(job_id, type: 'log', message: "[#{label}] ✅ ログインテスト成功")
      rescue => e
        conn&.update!(status: 'error', error_message: e.message.to_s[0, 500])
        broadcast_cable(job_id, type: 'log', message: "[#{label}] ❌ #{e.message[0, 200]}")
      ensure
        ctx.close rescue nil
        browser.close rescue nil
      end
    end

    broadcast_cable(job_id, type: 'done')
    broadcast_status(conn)
  rescue => e
    conn = ServiceConnection.find_by(service_name: service_name)
    conn&.update!(status: 'error', error_message: e.message.to_s[0, 500])
    broadcast_cable(job_id, type: 'done') if job_id
    broadcast_status(conn)
  end

  # 旧API互換（connection_id のみ）
  def perform_legacy(connection_id)
    conn = ServiceConnection.find(connection_id)
    perform_with_job_id(SecureRandom.hex(8), conn.service_name)
  end

  def broadcast_cable(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end

  def broadcast_status(conn)
    return unless conn
    ActionCable.server.broadcast('service_connections', {
      type: 'status_update',
      data: conn.as_json_safe,
    })
  end

  def find_playwright_path
    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    if File.exist?(local)
      wrapper = '/tmp/playwright-runner.sh'
      File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
      File.chmod(0o755, wrapper)
      return wrapper
    end
    'npx playwright'
  end
end
