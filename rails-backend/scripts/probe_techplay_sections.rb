require 'playwright'
require 'shellwords'
require 'json'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '995222')

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

  page.goto("https://owner.techplay.jp/event/#{EVENT_ID}/edit", waitUntil: 'domcontentloaded')
  page.wait_for_timeout(4000)

  # ページ全体から putEvent を持つ Vue component を全部列挙し、
  # それぞれの $data.input のキーと値ダンプを返す
  result = page.evaluate(<<~JS)
    (() => {
      const seen = new Set();
      const out = [];
      const walk = (el) => {
        if (!el || seen.has(el)) return;
        seen.add(el);
        const v = el.__vue__;
        if (v && typeof v.putEvent === 'function') {
          const inp = v.input || {};
          const dump = {};
          for (const k of Object.keys(inp)) {
            const val = inp[k];
            if (val === null || val === undefined) { dump[k] = null; continue; }
            const t = typeof val;
            if (t === 'string') dump[k] = val.slice(0, 120);
            else if (t === 'number' || t === 'boolean') dump[k] = val;
            else if (Array.isArray(val)) dump[k] = `[array len=${val.length}]`;
            else dump[k] = `[object keys=${Object.keys(val).slice(0,5).join(',')}]`;
          }
          // セクション識別のため、上位の見出しテキストを取りに行く
          let cur = el; let header = '';
          for (let i = 0; i < 12 && cur && !header; i++) {
            const h = cur.querySelector && cur.querySelector('h2, h3, .title, .heading, .label');
            if (h && h.innerText.trim()) { header = h.innerText.trim().slice(0, 50); break; }
            cur = cur.parentElement;
          }
          out.push({ class: (el.className||'').toString().slice(0,80), header, input_keys: Object.keys(inp), input_dump: dump, methods: Object.keys(v.$options.methods || {}).slice(0, 20) });
        }
        for (const child of el.children) walk(child);
      };
      walk(document.body);
      return out;
    })()
  JS

  puts "===== putEvent を持つ全 Vue components ====="
  result.each_with_index do |c, i|
    puts "\n[##{i}] class=\"#{c['class']}\" header=「#{c['header']}」"
    puts "  input_keys: #{c['input_keys'].inspect}"
    puts "  input_dump: #{c['input_dump'].inspect}"
    puts "  methods: #{c['methods'].inspect}"
  end

  browser.close
end
