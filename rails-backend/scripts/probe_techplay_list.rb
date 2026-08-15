require 'playwright'
require 'shellwords'
require 'json'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'])
  context = browser.new_context
  page = context.new_page

  page.goto('https://owner.techplay.jp/auth')
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  page.goto('https://owner.techplay.jp/event', waitUntil: 'domcontentloaded')
  page.wait_for_timeout(4000)

  # DOM ダンプ：各イベント行の生 HTML を一行分だけ確認
  rows_html = page.evaluate(<<~JS)
    (() => {
      const out = [];
      const candidates = document.querySelectorAll('table tbody tr, .event-list-row, .eventList_item, li.list-item, [class*="EventList"]');
      for (const r of candidates) {
        const links = [...r.querySelectorAll('a')].map(a => a.href).filter(h => /\\/event\\/\\d+/.test(h));
        if (!links.length) continue;
        out.push({ html: r.outerHTML.slice(0, 600), links: [...new Set(links)] });
        if (out.length >= 20) break;
      }
      return out;
    })()
  JS
  puts "===== row HTML サンプル (最大20件) ====="
  rows_html.each_with_index { |r, i| puts "\n[##{i}] links=#{r['links'].inspect}\n#{r['html']}" }

  # Vue ルートから window.app などを探って一覧を取得できないか試す
  app_dump = page.evaluate(<<~JS)
    (() => {
      const findVueRoot = () => {
        const all = document.querySelectorAll('*');
        for (const el of all) {
          if (el.__vue_app__) return el.__vue_app__;
          if (el.__vue__ && el.__vue__.$root) return el.__vue__.$root;
        }
        return null;
      };
      const root = findVueRoot();
      if (!root) return { found: false };
      const data = root.$data || {};
      const keys = Object.keys(data);
      return { found: true, keys, sample: keys.slice(0,30) };
    })()
  JS
  puts "\n===== Vue root $data ====="
  puts JSON.pretty_generate(app_dump)

  # イベント詳細を一件 fetch してみて publish_state を取得
  if rows_html.any?
    first_link = rows_html.first['links'].first
    if first_link =~ %r{/event/(\d+)}
      eid = $1
      page.goto("https://owner.techplay.jp/event/#{eid}/edit", waitUntil: 'domcontentloaded')
      page.wait_for_timeout(3500)
      pub = page.evaluate(<<~JS)
        (() => {
          const seen = new Set();
          const found = [];
          const walk = (el) => {
            if (!el || seen.has(el)) return;
            seen.add(el);
            const v = el.__vue__;
            if (v && v.input) {
              const inp = v.input;
              if ('publish_state' in inp || 'release_at' in inp) {
                const dump = {};
                for (const k of Object.keys(inp)) {
                  const val = inp[k];
                  if (val && typeof val === 'object') dump[k] = Array.isArray(val) ? `[arr ${val.length}]` : '[obj]';
                  else dump[k] = val;
                }
                found.push(dump);
              }
            }
            for (const c of el.children) walk(c);
          };
          walk(document.body);
          return found;
        })()
      JS
      puts "\n===== /event/#{eid}/edit の publish 関連 input dump ====="
      puts JSON.pretty_generate(pub)
    end
  end

  browser.close
end
