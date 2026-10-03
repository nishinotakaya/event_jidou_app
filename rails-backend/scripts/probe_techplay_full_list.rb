# 全ページの /event 一覧をスクレイプして JSON で出力。
# 各行: { id:, title:, status: '公開中'|'非公開', ended:, started_at:, ended_at:, capacity: }
require 'playwright'
require 'shellwords'
require 'json'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

all = []

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'])
  context = browser.new_context
  page = context.new_page

  page.goto('https://owner.techplay.jp/auth')
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  page_no = 1
  loop do
    url = "https://owner.techplay.jp/event?page=#{page_no}"
    page.goto(url, waitUntil: 'domcontentloaded')
    page.wait_for_timeout(2500)

    rows = page.evaluate(<<~JS)
      (() => {
        const out = [];
        const trs = document.querySelectorAll('table tbody tr');
        for (const r of trs) {
          const tds = r.querySelectorAll('td');
          if (tds.length < 8) continue;
          const id = (tds[0].innerText || '').trim();
          const labels = [...tds[1].querySelectorAll('.label')].map(l => l.innerText.trim());
          const link = r.querySelector('a[href*="/event/"]');
          const title = (tds[2].innerText || '').trim();
          const cap = (tds[4].innerText || '').trim();
          const reg = (tds[5].innerText || '').trim();
          const start = (tds[6].innerText || '').trim();
          const end = (tds[7].innerText || '').trim();
          out.push({ id, labels, title, cap, reg, start, end });
        }
        return out;
      })()
    JS

    break if rows.empty?
    rows.each { |r| r['page'] = page_no }
    all.concat(rows)
    puts "page #{page_no}: #{rows.size} 件"
    page_no += 1
    break if page_no > 20  # safety cap
  end

  # 公開中の1件・非公開の1件 から publish_state の生値を取得
  pub_event = all.find { |r| r['labels'].include?('公開中') && !r['labels'].include?('終了') } ||
              all.find { |r| r['labels'].include?('公開中') }
  np_event  = all.find { |r| r['labels'].include?('非公開') && !r['labels'].include?('終了') }
  state_dump = {}
  [pub_event, np_event].compact.each do |r|
    page.goto("https://owner.techplay.jp/event/#{r['id']}/edit", waitUntil: 'domcontentloaded')
    page.wait_for_timeout(3000)
    inputs = page.evaluate(<<~JS)
      (() => {
        const found = [];
        const seen = new Set();
        const walk = (el) => {
          if (!el || seen.has(el)) return; seen.add(el);
          const v = el.__vue__;
          if (v && v.input && ('publish_state' in v.input || 'release_at' in v.input)) {
            const inp = v.input; const dump = {};
            for (const k of Object.keys(inp)) {
              const val = inp[k];
              if (val && typeof val === 'object') dump[k] = Array.isArray(val) ? `[arr ${val.length}]` : '[obj]';
              else dump[k] = val;
            }
            found.push(dump);
          }
          for (const c of el.children) walk(c);
        };
        walk(document.body);
        return found;
      })()
    JS
    state_dump[r['id']] = { labels: r['labels'], inputs: inputs }
  end

  out = { all: all, state_samples: state_dump }
  File.write('/tmp/techplay_listing.json', JSON.pretty_generate(out))
  puts "\n総件数 #{all.size} → /tmp/techplay_listing.json"
  puts JSON.pretty_generate(state_dump)

  browser.close
end
