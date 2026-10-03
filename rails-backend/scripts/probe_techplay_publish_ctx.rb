require 'playwright'
require 'shellwords'
require 'json'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '994978')

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox'])
  context = browser.new_context
  page = context.new_page

  page.goto('https://owner.techplay.jp/auth')
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  page.goto("https://owner.techplay.jp/event/#{EVENT_ID}/edit", waitUntil: 'domcontentloaded')
  page.wait_for_timeout(4000)

  ctx = page.evaluate(<<~JS)
    (() => {
      const out = [];
      const btns = [...document.querySelectorAll('button, a')]
        .filter(b => /^\\s*(公開する|限定公開にする|公開予約する|公開停止)\\s*$/.test((b.innerText||'').replace(/\\n/g,' ').trim()));
      for (const b of btns) {
        // 親 5 階層分の class を辿る
        const ancestors = [];
        let cur = b.parentElement;
        for (let i = 0; i < 8 && cur; i++) {
          ancestors.push({ tag: cur.tagName, cls: (cur.className||'').toString().slice(0,80), id: cur.id || '' });
          cur = cur.parentElement;
        }
        // 直近の見出し
        let header = '';
        cur = b;
        for (let i = 0; i < 12 && cur && !header; i++) {
          const h = cur.querySelector ? cur.querySelector('h1, h2, h3, .title, .heading, .label') : null;
          if (h && h.innerText.trim()) { header = h.innerText.trim().slice(0, 60); break; }
          cur = cur.parentElement;
        }
        // 直近 putEvent / クリックハンドラを探す
        cur = b;
        let methodName = '';
        for (let i = 0; i < 12 && cur; i++) {
          const v = cur.__vue__;
          if (v && v.$options && v.$options.methods) {
            const ms = Object.keys(v.$options.methods);
            const hit = ms.find(m => /publish|release|toPublic|public|open|状態/.test(m));
            if (hit) { methodName = hit + ' (in ' + (cur.tagName) + ')'; break; }
          }
          cur = cur.parentElement;
        }
        out.push({ text: b.innerText.trim(), header, methodName, ancestors, html: b.outerHTML.slice(0,200) });
      }
      return out;
    })()
  JS
  puts JSON.pretty_generate(ctx)

  # ページ全体で 'publish_state' が現れる場所を grep
  grep = page.evaluate(<<~JS)
    (() => {
      const html = document.documentElement.outerHTML;
      const idxs = [];
      const re = /publish_state|release_at|publishState|releaseAt/g;
      let m;
      while ((m = re.exec(html)) !== null) {
        idxs.push({ index: m.index, snippet: html.slice(Math.max(0,m.index-60), m.index+80) });
        if (idxs.length > 20) break;
      }
      return idxs;
    })()
  JS
  puts "\n===== publish_state 出現箇所 ====="
  puts JSON.pretty_generate(grep)

  browser.close
end
