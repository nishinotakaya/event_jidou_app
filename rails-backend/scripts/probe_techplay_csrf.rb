require 'playwright'
require 'shellwords'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '995222')

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

last_put_request = nil

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox'])
  context = browser.new_context
  page = context.new_page

  page.on('request', ->(r) {
    next unless r.url == "https://owner.techplay.jp/event/#{EVENT_ID}/edit" && r.method == 'POST'
    last_put_request = { url: r.url, method: r.method, post_data: r.post_data, headers: r.headers }
  })

  page.goto('https://owner.techplay.jp/auth')
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  page.goto("https://owner.techplay.jp/event/#{EVENT_ID}/edit", waitUntil: 'domcontentloaded')
  page.wait_for_timeout(3500)

  # ページ内の CSRF token を全部探す
  csrf = page.evaluate(<<~JS)
    (() => {
      const out = {};
      // <meta name="csrf-token">
      const meta = document.querySelector('meta[name="csrf-token"], meta[name="_token"]');
      out.meta = meta ? { name: meta.name, content: meta.content } : null;
      // input[name=_token]
      const tokenInput = document.querySelector('input[name="_token"]');
      out.input_token = tokenInput ? tokenInput.value : null;
      // window.Laravel
      out.window_laravel = window.Laravel || null;
      // axios default headers
      try { out.axios_common = window.axios && window.axios.defaults && window.axios.defaults.headers && window.axios.defaults.headers.common; } catch(e) {}
      return out;
    })()
  JS
  puts "===== CSRF 候補 ====="
  puts csrf.inspect

  # 既知のキー (markdown_privacy_policy) を再保存させてヘッダを観察
  page.evaluate(<<~JS)
    (() => {
      const wrappers = [...document.querySelectorAll('.toastui-editor-defaultUI')];
      let component = null;
      for (const w of wrappers) {
        let cur = w;
        for (let i = 0; i < 25 && cur; i++) {
          const v = cur.__vue__;
          if (v && v.input && 'markdown_privacy_policy' in v.input) { component = v; break; }
          cur = cur.parentElement;
        }
        if (component) break;
      }
      if (component) component.putEvent();
    })()
  JS
  page.wait_for_timeout(3000)

  if last_put_request
    puts "\n===== 観察した PUT リクエスト ====="
    puts "URL: #{last_put_request[:url]}"
    puts "Method: #{last_put_request[:method]}"
    puts "Headers:"
    last_put_request[:headers].each { |k, v| puts "  #{k}: #{v}" }
    puts "Post data: #{last_put_request[:post_data].force_encoding('UTF-8')}"
  else
    puts "\n[!] PUT リクエストがキャプチャされず"
  end

  # cookie もダンプ
  cookies = context.cookies
  puts "\n===== cookies ====="
  cookies.each { |c| puts "  #{c['name']}=#{c['value'].to_s[0,30]}... (domain=#{c['domain']})" }

  browser.close
end
