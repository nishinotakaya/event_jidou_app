# 非公開イベントの edit ページに行き、公開ボタン or related method を捜索。
# クリックして実 API リクエストを記録する。
require 'playwright'
require 'shellwords'
require 'json'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '995279')  # テストイベントを公開してみる

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

records = []
@phase = 'init'

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'])
  context = browser.new_context
  page = context.new_page

  page.on('request',  ->(r) { records << { phase: @phase, dir: 'req', method: r.method, url: r.url, post_data: r.post_data, headers: r.headers } })
  page.on('response', ->(r) { records << { phase: @phase, dir: 'res', status: r.status, url: r.url } })

  @phase = 'login'
  page.goto('https://owner.techplay.jp/auth')
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  @phase = 'goto_edit'
  page.goto("https://owner.techplay.jp/event/#{EVENT_ID}/edit", waitUntil: 'domcontentloaded')
  page.wait_for_timeout(4000)

  # 全 Vue コンポーネントから 'publish' を含むメソッドを列挙
  methods_dump = page.evaluate(<<~JS)
    (() => {
      const out = []; const seen = new Set();
      const walk = (el) => {
        if (!el || seen.has(el)) return; seen.add(el);
        const v = el.__vue__;
        if (v && v.$options && v.$options.methods) {
          const ms = Object.keys(v.$options.methods).filter(m => /publish|release|public|open/i.test(m));
          if (ms.length) {
            const inputKeys = v.input ? Object.keys(v.input) : [];
            out.push({ class: (el.className||'').toString().slice(0,80), methods: ms, inputKeys });
          }
        }
        for (const c of el.children) walk(c);
      };
      walk(document.body);
      return out;
    })()
  JS
  puts "===== publish 系メソッドを持つ component ====="
  puts JSON.pretty_generate(methods_dump)

  # 「公開する」ボタンの場所と DOM
  puts "\n===== 公開ボタン HTML 探索 ====="
  btn_html = page.evaluate(<<~JS)
    (() => {
      const buttons = [...document.querySelectorAll('button, a')];
      return buttons
        .filter(b => /公開|公開する|限定|下書き/.test(b.innerText || ''))
        .map(b => ({ text: b.innerText.trim().slice(0,40), tag: b.tagName, html: b.outerHTML.slice(0,300) }))
        .slice(0, 30);
    })()
  JS
  puts JSON.pretty_generate(btn_html)

  # スクロールしてから「公開する」ボタンを実クリック → 実際の HTTP を記録
  records.clear
  @phase = 'click_publish'
  page.evaluate('() => window.scrollTo(0, document.body.scrollHeight)')
  page.wait_for_timeout(1500)

  result = page.evaluate(<<~JS)
    (() => {
      const targets = [...document.querySelectorAll('button, a')]
        .filter(b => /^\\s*公開する\\s*$/.test(b.innerText || ''));
      if (!targets.length) return { ok: false, reason: '公開する ボタン未発見' };
      // ボタン自身をスクロール
      targets[0].scrollIntoView({ block: 'center' });
      targets[0].click();
      return { ok: true, count: targets.length, html: targets[0].outerHTML.slice(0,300) };
    })()
  JS
  puts "\n===== クリック試行 ====="
  puts JSON.pretty_generate(result)
  page.wait_for_timeout(2500)

  # モーダルが出ていれば確認ボタン
  modal = page.evaluate(<<~JS)
    (() => {
      const m = document.querySelector('.modal.is-active, .dialog.modal.is-active, .modal.show');
      if (!m) return null;
      return {
        text: m.innerText.slice(0, 300),
        buttons: [...m.querySelectorAll('button, a')].map(b => b.innerText.trim()).slice(0,8),
      };
    })()
  JS
  puts "\n===== モーダル ====="
  puts JSON.pretty_generate(modal)

  # ※ モーダルの確認は押さない（実公開を避ける） — 構造だけ取って次へ

  browser.close
end

# 出力
puts "\n===== click_publish の HTTP =====\n"
records.each do |r|
  next if r[:dir] == 'res'
  next if r[:method] == 'GET'
  next if r[:url] =~ /google|clarity|gtm|analytics|fonts/
  puts "#{r[:method]} #{r[:url]}"
  if r[:post_data]
    body = r[:post_data].to_s.dup.force_encoding('UTF-8')
    body = '[binary]' unless body.valid_encoding?
    puts "  payload(#{body.bytesize}B): #{body[0,1500]}"
  end
end
puts "\n----- レスポンス -----\n"
records.each do |r|
  next unless r[:dir] == 'res'
  next if r[:url] =~ /google|clarity|gtm|analytics|fonts/
  puts "  #{r[:status]} #{r[:url]}"
end
