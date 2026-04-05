require 'playwright'
require 'shellwords'

class TestConnectionJob < ApplicationJob
  queue_as :default

  TEST_CONFIGS = {
    'kokuchpro' => {
      url: 'https://www.kokuchpro.com/login/',
      email_sel: '#LoginFormEmail',
      pass_sel: '#LoginFormPassword',
      submit_sel: '#LoginFormBtn',
      success_check: ->(page) { !page.url.include?('/login') },
    },
    'connpass' => {
      url: 'https://connpass.com/login/',
      email_sel: 'input[name="username"],input[name="email"]',
      pass_sel: 'input[name="password"]',
      submit_sel: 'button[type="submit"]',
      success_check: ->(page) { !page.url.include?('/login') },
    },
    'peatix' => {
      url: 'https://peatix.com/signin',
      email_sel: 'input[name="username"]',
      pass_sel: 'input[type="password"]',
      submit_sel: 'button[type="submit"]',
      success_check: ->(page) { !page.url.include?('/signin') },
    },
    'techplay' => {
      url: 'https://owner.techplay.jp/auth',
      email_sel: '#email',
      pass_sel: '#password',
      submit_sel: "input[type='submit']",
      success_check: ->(page) { !page.url.include?('/auth') || page.url.include?('select_menu') },
    },
    'zoom' => {
      url: 'https://zoom.us/signin',
      email_sel: '#email',
      pass_sel: '#password',
      submit_sel: 'button[type="submit"],#js_btn_login',
      success_check: ->(page) { page.url.include?('zoom.us/profile') || page.url.include?('zoom.us/meeting') || !page.url.include?('/signin') },
    },
    'lme' => {
      url: 'https://page.line-and.me/',
      email_sel: 'input[type="email"],input[name="email"]',
      pass_sel: 'input[type="password"],input[name="password"]',
      submit_sel: 'button[type="submit"]',
      success_check: ->(page) { !page.url.include?('/login') && !page.url.include?('/signin') },
    },
    'doorkeeper' => {
      url: 'https://manage.doorkeeper.jp/user/sign_in',
      email_sel: 'input[name="user[email]"]',
      pass_sel: 'input[name="user[password]"]',
      submit_sel: 'input[type="submit"],button[type="submit"]',
      success_check: ->(page) { !page.url.include?('/sign_in') },
    },
    'seminars' => {
      url: 'https://seminars.jp/login',
      email_sel: 'input[name="email"],input[type="email"],#email',
      pass_sel: 'input[name="password"],input[type="password"],#password',
      submit_sel: 'button[type="submit"],input[type="submit"]',
      success_check: ->(page) { !page.url.include?('/login') },
    },
    'onclass' => {
      url: 'https://manager.the-online-class.com/sign_in',
      email_sel: 'input[name="email"]',
      pass_sel: 'input[name="password"]',
      submit_sel: 'button:has-text("ログインする")',
      success_check: ->(page) { !page.url.include?('/sign_in') },
    },
  }.freeze

  def perform(connection_id)
    conn = ServiceConnection.find(connection_id)
    config = TEST_CONFIGS[conn.service_name]

    unless config
      conn.update!(status: 'error', error_message: '接続テスト未対応のサービスです')
      broadcast(conn)
      return
    end

    conn.update!(status: 'testing', error_message: nil)
    broadcast(conn)

    playwright_path = find_playwright_path
    result = nil

    Playwright.create(playwright_cli_executable_path: playwright_path) do |pw|
      browser = pw.chromium.launch(
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled']
      )
      context = browser.new_context(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 }
      )
      page = context.new_page

      page.goto(config[:url], waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      # メール入力
      page.fill(config[:email_sel], conn.email.to_s)
      # パスワード入力
      page.fill(config[:pass_sel], conn.password_field.to_s)
      # 送信
      page.click(config[:submit_sel])
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      if config[:success_check].call(page)
        result = { status: 'connected', error: nil }
        # セッションをDBに保存（次回のJob実行で復元用）
        begin
          state = context.storage_state
          conn.update!(session_data: state.to_json)
        rescue => e
          Rails.logger.warn "[TestConnection] セッション保存失敗: #{e.message}"
        end
      else
        result = { status: 'error', error: "ログイン失敗（URL: #{page.url}）" }
      end

      context.close rescue nil
      browser.close rescue nil
    end

    if result
      conn.update!(
        status: result[:status],
        error_message: result[:error],
        last_connected_at: result[:status] == 'connected' ? Time.current : conn.last_connected_at
      )
    end

    broadcast(conn)
  rescue => e
    conn = ServiceConnection.find_by(id: connection_id)
    conn&.update!(status: 'error', error_message: e.message)
    broadcast(conn) if conn
  end

  private

  def broadcast(conn)
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
      unless File.exist?(wrapper)
        File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
        File.chmod(0o755, wrapper)
      end
      return wrapper
    end
    'npx playwright'
  end
end
