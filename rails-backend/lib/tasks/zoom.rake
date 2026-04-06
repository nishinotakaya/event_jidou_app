namespace :zoom do
  desc 'ブラウザを開いてZoomに手動ログイン → セッションをDBに保存'
  task login: :environment do
    require 'playwright'
    require 'shellwords'

    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    wrapper = '/tmp/playwright-runner.sh'
    unless File.exist?(wrapper) && File.read(wrapper).include?(local)
      File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
      File.chmod(0o755, wrapper)
    end

    Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
      browser = pw.chromium.launch(headless: false, args: ['--no-sandbox'])
      context = browser.new_context(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      )
      page = context.new_page
      page.goto('https://zoom.us/signin')

      puts "\n=========================================="
      puts "ブラウザでZoomにログインしてください"
      puts "CAPTCHAがあれば手動で通してください"
      puts "ログイン完了後、Enterキーを押してください"
      puts "=========================================="
      $stdin.gets

      state = context.storage_state
      conn = ServiceConnection.find_by(service_name: 'zoom')
      if conn
        conn.update!(session_data: state.to_json, last_connected_at: Time.current)
        puts "✅ Zoomセッションを保存しました"
      else
        puts "❌ ServiceConnection 'zoom' が見つかりません"
      end

      browser.close
    end
  end

  desc 'Heroku上でZoomログインをテスト（headless）'
  task test: :environment do
    $stdout.sync = true
    require 'playwright'
    require 'shellwords'

    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    wrapper = '/tmp/playwright-runner.sh'
    File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
    File.chmod(0o755, wrapper)

    puts "1. Starting Playwright..."
    Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
      puts "2. Launching browser..."
      browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'])
      context = browser.new_context(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      )
      page = context.new_page

      puts "3. Navigating to zoom.us/signin..."
      page.goto('https://zoom.us/signin', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
      page.wait_for_timeout(2000)
      puts "4. URL: #{page.url}"

      conn = ServiceConnection.find_by(service_name: 'zoom')
      puts "5. Email: #{conn&.email}"

      page.locator('input[type="email"], input[name="email"], #email').first.fill(conn.email)
      page.locator('button:has-text("次へ"), button:has-text("Next"), button[type="submit"]').first.click
      page.wait_for_timeout(3000)

      puts "6. Filling password..."
      page.locator('input[type="password"]').first.wait_for(state: 'visible', timeout: 10_000)
      page.locator('input[type="password"]').first.fill(conn.password_field)

      puts "7. Clicking signin..."
      page.locator('button:has-text("サインイン"), button:has-text("Sign In"), button[type="submit"]').first.click
      page.wait_for_timeout(8000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

      puts "8. URL after signin: #{page.url}"
      login_page = page.url.include?('/signin') || page.url.include?('/login')
      puts "9. Still on login page: #{login_page}"
      body = page.evaluate('document.body.innerText.substring(0, 500)') rescue 'ERROR'
      puts "10. Body: #{body}"

      if !login_page
        puts "11. LOGIN SUCCESS! Saving session..."
        state = context.storage_state
        conn.update!(session_data: state.to_json, last_connected_at: Time.current)
        puts "12. Session saved to DB"
      else
        puts "11. LOGIN FAILED"
      end

      browser.close
      puts "Done."
    end
  rescue => e
    puts "ERROR: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end
