require 'playwright'

namespace :zoom do
  desc 'Zoomに手動ログインしてセッションを保存（初回 or セッション切れ時に実行）'
  task login: :environment do
    playwright_path = find_playwright_path
    storage_path = Rails.root.join('tmp', 'zoom_session.json').to_s

    puts "🔐 Zoomログインセッション保存ツール"
    puts "   ブラウザが開きます。Zoomにログインしてください。"
    puts "   ログイン完了後、ミーティング一覧が表示されたらEnterキーを押してください。"
    puts ""

    Playwright.create(playwright_cli_executable_path: playwright_path) do |pw|
      browser = pw.chromium.launch(
        headless: false,
        args: ['--disable-blink-features=AutomationControlled'],
      )

      context = browser.new_context(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      )

      page = context.new_page

      # Pre-fill email if available
      email = ENV['ZOOM_EMAIL'].to_s
      page.goto('https://zoom.us/signin', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

      if email.present?
        begin
          email_input = page.locator('input[type="email"], input[name="email"], #email').first
          email_input.wait_for(state: 'visible', timeout: 5_000)
          email_input.fill(email)
          puts "📧 メールアドレスを自動入力しました: #{email}"
        rescue
          puts "📧 メールアドレスの自動入力に失敗。手動で入力してください。"
        end
      end

      puts ""
      puts "👆 ブラウザでログインを完了してください。"
      puts "   ログイン後、Enterキーを押すとセッションを保存します。"
      $stdin.gets

      # Save storage state
      context.storage_state(path: storage_path)
      puts ""
      puts "✅ セッションを保存しました: #{storage_path}"
      puts "   今後の自動作成はこのセッションを使用します。"

      browser.close
    end
  end
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
