require 'playwright'
require 'shellwords'

class BrowserLoginJob < ApplicationJob
  queue_as :default

  CONFIGS = {
    'tunagate' => {
      url: 'https://tunagate.com/users/sign_in?ifx=yBrPZyXgNqee6MeA',
      session_path: -> { Rails.root.join('tmp', 'tunagate_session.json').to_s },
      success_check: ->(url) { url.include?('tunagate.com') && !url.include?('sign_in') },
    },
    'luma' => {
      url: 'https://lu.ma/signin',
      session_path: -> { Rails.root.join('tmp', 'luma_session.json').to_s },
      success_check: ->(url) { url.include?('luma.com') && !url.include?('/signin') },
    },
    'passmarket' => {
      url: 'https://passmarket.yahoo.co.jp/',
      session_path: -> { Rails.root.join('tmp', 'passmarket_session.json').to_s },
      success_check: ->(url) { url.include?('passmarket.yahoo.co.jp') && (url.include?('/mypage') || url.include?('/event')) },
    },
    'jimoty' => {
      url: 'https://jmty.jp/login',
      session_path: -> { Rails.root.join('tmp', 'jimoty_session.json').to_s },
      success_check: ->(url) { url.include?('jmty.jp') && !url.include?('/login') && !url.include?('/sign_up') },
    },
    'twitter' => {
      url: 'https://x.com/i/flow/login',
      session_path: -> { Rails.root.join('tmp', 'twitter_session.json').to_s },
      success_check: ->(url) { url.include?('x.com/home') || (url.include?('x.com') && !url.include?('login') && !url.include?('flow')) },
    },
    'instagram' => {
      url: 'https://www.instagram.com/accounts/login/',
      session_path: -> { Rails.root.join('tmp', 'instagram_session.json').to_s },
      success_check: ->(url) { url.include?('instagram.com') && !url.include?('/login') && !url.include?('/accounts/login') },
    },
  }.freeze

  def perform(job_id, service_name)
    config = CONFIGS[service_name]
    unless config
      broadcast(job_id, type: 'error', message: "#{service_name} はブラウザログイン非対応です")
      broadcast(job_id, type: 'done')
      return
    end

    broadcast(job_id, type: 'log', message: "#{service_name} のブラウザを起動中...")

    playwright_path = find_playwright_path
    session_path = config[:session_path].call

    Playwright.create(playwright_cli_executable_path: playwright_path) do |pw|
      browser = pw.chromium.launch(
        headless: ENV["RAILS_ENV"] == "production",
        args: ['--no-sandbox', '--disable-blink-features=AutomationControlled']
      )
      context = browser.new_context(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      )
      page = context.new_page

      broadcast(job_id, type: 'log', message: 'サインインページを開きました。ブラウザでログインしてください。')
      page.goto(config[:url], waitUntil: 'networkidle', timeout: 30_000)

      # ユーザーがログインするのを待つ（最大3分）
      180.times do |i|
        sleep 1
        current_url = page.url rescue ''
        if config[:success_check].call(current_url)
          context.storage_state(path: session_path)
          broadcast(job_id, type: 'log', message: "✅ ログイン成功！セッションを保存しました。")
          broadcast(job_id, type: 'result', data: { status: 'connected', service: service_name })

          # service_connectionも更新
          conn = ServiceConnection.find_by(service_name: service_name)
          conn&.update!(status: 'connected', last_connected_at: Time.current, error_message: nil)

          broadcast(job_id, type: 'done')
          browser.close rescue nil
          return
        end
        broadcast(job_id, type: 'log', message: "ログイン待機中... (#{i + 1}秒)") if (i + 1) % 15 == 0
      end

      # タイムアウト — それでもセッション保存
      context.storage_state(path: session_path)
      broadcast(job_id, type: 'log', message: '⚠️ タイムアウト。セッションは保存しました。')
      broadcast(job_id, type: 'done')
      browser.close rescue nil
    end
  rescue => e
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
      File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"\$@\"\n")
      File.chmod(0o755, wrapper)
      return wrapper
    end
    'npx playwright'
  end
end
