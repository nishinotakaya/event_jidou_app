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
end
