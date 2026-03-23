namespace :tunagate do
  desc "つなゲートにGoogleログインしてセッションを保存（初回のみ手動で2段階認証を通す）"
  task login: :environment do
    require 'playwright'
    require 'shellwords'

    session_path = Rails.root.join('tmp', 'tunagate_session.json').to_s
    playwright_path = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    wrapper = '/tmp/playwright-runner.sh'
    unless File.exist?(wrapper)
      File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_path)} \"$@\"\n")
      File.chmod(0o755, wrapper)
    end

    Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
      browser = pw.chromium.launch(
        headless: false,
        args: ['--no-sandbox', '--disable-blink-features=AutomationControlled']
      )
      context = browser.new_context(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 }
      )
      page = context.new_page

      puts "つなゲートのサインインページを開きます..."
      page.goto("https://tunagate.com/users/sign_in?ifx=yBrPZyXgNqee6MeA", waitUntil: "networkidle", timeout: 30_000)
      puts "ブラウザでGoogleログインして、つなゲートのメニュー画面が表示されるまで操作してください。"
      puts "完了したらEnterキーを押してください..."
      $stdin.gets

      current_url = page.url
      puts "現在のURL: #{current_url}"

      # URLに関わらずセッションを保存（Googleセッションも含まれる）
      context.storage_state(path: session_path)
      puts "✅ セッションを保存しました: #{session_path}"

      browser.close rescue nil
    end
  end
end
