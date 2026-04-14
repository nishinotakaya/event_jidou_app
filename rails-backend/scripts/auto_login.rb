# 使い方: bundle exec rails runner scripts/auto_login.rb facebook
# 対応: facebook / instagram / threads
# 動作: 可視ブラウザでログイン画面を開き、.env の認証情報を自動入力。
#       2FA/CAPTCHA が出たら手動で突破してください。成功後にセッションを
#       ServiceConnection.session_data に保存します。

require 'playwright'
require 'shellwords'
require 'json'

SERVICE = (ARGV[0] || 'facebook').to_s.downcase

CONFIGS = {
  'facebook' => {
    url: 'https://www.facebook.com/login/',
    email_selector: 'input[name="email"], input#email, input[type="email"]',
    password_selector: 'input[name="pass"], input#pass, input[type="password"]',
    submit_selector: 'button[name="login"], button[data-testid="royal_login_button"], button[type="submit"]',
    success: ->(url) { url.include?('facebook.com') && !url.include?('/login') && !url.include?('checkpoint') && !url.include?('recover') },
    email_env: 'FACEBOOK_EMAIL', password_env: 'FACEBOOK_PASSWORD',
  },
  'instagram' => {
    url: 'https://www.instagram.com/accounts/login/',
    email_selector: 'input[name="username"]',
    password_selector: 'input[name="password"]',
    submit_selector: 'button[type="submit"]',
    success: ->(url) { url.include?('instagram.com') && !url.include?('/login') && !url.include?('/accounts/login') },
    email_env: 'INSTAGRAM_EMAIL', password_env: 'INSTAGRAM_PASSWORD',
  },
  'threads' => {
    url: 'https://www.threads.net/login',
    email_selector: 'input[autocomplete="username"]',
    password_selector: 'input[autocomplete="current-password"]',
    submit_selector: 'div[role="button"]:has-text("Log in"), div[role="button"]:has-text("ログイン")',
    success: ->(url) { url.include?('threads.net') && !url.include?('/login') },
    email_env: 'INSTAGRAM_EMAIL', password_env: 'INSTAGRAM_PASSWORD',
  },
}

cfg = CONFIGS[SERVICE] or abort("unknown service: #{SERVICE}")
email = ENV[cfg[:email_env]] or abort("#{cfg[:email_env]} が未設定")
password = ENV[cfg[:password_env]] or abort("#{cfg[:password_env]} が未設定")
session_path = Rails.root.join('tmp', "#{SERVICE}_session.json").to_s

playwright_local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

puts "[#{SERVICE}] 起動: #{cfg[:url]}"

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: false, args: ['--disable-blink-features=AutomationControlled'])
  ctx = browser.new_context(
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
    locale: 'ja-JP',
    viewport: { width: 1280, height: 800 },
  )
  page = ctx.new_page
  page.goto(cfg[:url], waitUntil: 'networkidle', timeout: 45_000) rescue page.goto(cfg[:url], waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_timeout(3000)

  # Cookieバナー/許諾ポップアップを閉じる（FB/IG共通）
  %w[button:has-text("Allow") button:has-text("Accept") button:has-text("すべて許可") button:has-text("許可") button:has-text("OK")].each do |sel|
    begin
      btn = page.locator(sel).first
      if (btn.visible?(timeout: 1000) rescue false)
        btn.click rescue nil
        page.wait_for_timeout(1000)
        puts "[#{SERVICE}] Cookieバナー閉じました (#{sel})"
        break
      end
    rescue
    end
  end

  # メール入力（可視待ち 15s）
  email_filled = false
  begin
    field = page.locator(cfg[:email_selector]).first
    field.wait_for(state: 'visible', timeout: 15_000)
    field.fill(email)
    email_filled = true
    puts "[#{SERVICE}] メール入力完了"
  rescue => e
    puts "[#{SERVICE}] ⚠️ メール欄自動入力失敗: #{e.message[0, 80]}"
    puts "[#{SERVICE}] → ブラウザで手動入力してください"
  end

  if email_filled
    begin
      f2 = page.locator(cfg[:password_selector]).first
      f2.wait_for(state: 'visible', timeout: 5_000)
      f2.fill(password)
      puts "[#{SERVICE}] パスワード入力完了"
    rescue => e
      puts "[#{SERVICE}] ⚠️ パスワード欄: #{e.message[0, 80]}"
    end
    begin
      page.locator(cfg[:submit_selector]).first.click(timeout: 5_000)
      puts "[#{SERVICE}] 送信ボタンクリック"
    rescue => e
      puts "[#{SERVICE}] ⚠️ 送信ボタン: Enterで送信"
      page.keyboard.press('Enter') rescue nil
    end
  end

  puts "[#{SERVICE}] ⏳ ログイン成功待機中（最大5分、CAPTCHA/2FA/本人確認はブラウザで対応してください）..."
  success = false
  300.times do |i|
    sleep 1
    begin
      current = page.url
      if cfg[:success].call(current)
        success = true
        break
      end
      puts "[#{SERVICE}] ...#{i + 1}s (#{current[0, 80]})" if (i + 1) % 15 == 0
    rescue => e
      puts "[#{SERVICE}] page.url取得失敗: #{e.message}"
    end
  end

  # 成否にかかわらず、現在のstorage_stateは保存する（部分的でも再利用する価値あり）
  begin
    ctx.storage_state(path: session_path)
    state_json = File.read(session_path)

    conn = ServiceConnection.find_or_initialize_by(service_name: SERVICE)
    conn.email ||= email
    conn.session_data = state_json
    conn.status = success ? 'connected' : 'error'
    conn.last_connected_at = Time.current if success
    conn.error_message = success ? nil : "手動ログインタイムアウト (5分)"
    conn.save!

    if success
      puts "[#{SERVICE}] ✅ ログイン成功。セッションを DB (id=#{conn.id}) に保存しました"
    else
      puts "[#{SERVICE}] ⚠️ タイムアウトしましたが、途中セッションを DB (id=#{conn.id}) に保存しました"
    end
    puts "[#{SERVICE}] session_data_size=#{state_json.bytesize}B"
    puts "[#{SERVICE}] セッションJSON → #{session_path}"
  rescue => e
    puts "[#{SERVICE}] セッション保存失敗: #{e.message}"
  end

  sleep 2
  browser.close rescue nil
end
