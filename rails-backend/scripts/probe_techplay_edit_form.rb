require 'playwright'
require 'shellwords'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '995222')

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

  page.on('request',  ->(r) { records << { phase: @phase, dir: 'req', method: r.method, url: r.url, post_data: r.post_data } })
  page.on('response', ->(r) { records << { phase: @phase, dir: 'res', status: r.status, url: r.url } })

  # Login
  @phase = 'login'
  page.goto('https://owner.techplay.jp/auth')
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  # Edit page
  @phase = 'goto_edit'
  page.goto("https://owner.techplay.jp/event/#{EVENT_ID}/edit", waitUntil: 'domcontentloaded')
  page.wait_for_timeout(3000)

  # ===== form と input を全列挙 =====
  forms = page.evaluate(<<~JS)
    (() => {
      const out = [];
      document.querySelectorAll('form').forEach((f, i) => {
        const inputs = [];
        f.querySelectorAll('input, textarea, select').forEach(el => {
          inputs.push({ tag: el.tagName, type: el.type || '', name: el.name || '', id: el.id || '', value: (el.value || '').toString().slice(0, 60) });
        });
        out.push({
          idx: i,
          action: f.action,
          method: f.method,
          enctype: f.enctype,
          input_count: inputs.length,
          inputs,
        });
      });
      return out;
    })()
  JS

  puts "===== <form> 一覧 ====="
  forms.each do |f|
    puts "##{f['idx']} action=#{f['action']} method=#{f['method']} enctype=#{f['enctype']} (#{f['input_count']} inputs)"
    f['inputs'].each { |i| puts "    <#{i['tag'].downcase} type=#{i['type']} name=\"#{i['name']}\" id=\"#{i['id']}\"> = #{i['value'].inspect}" }
  end

  # ===== Toast UI Editor の Vue ref が紐づく親 component の data を探る =====
  vue_info = page.evaluate(<<~JS)
    (() => {
      const wrappers = [...document.querySelectorAll('.toastui-editor-defaultUI')];
      const ed = wrappers[wrappers.length - 1];
      let cur = ed; const trail = [];
      for (let i = 0; i < 25 && cur; i++) {
        const v = cur.__vue__;
        if (v) {
          const props = Object.keys(v.$props || {});
          const data  = Object.keys(v.$data  || {});
          const refs  = Object.keys(v.$refs  || {});
          const methods = (v.$options && v.$options.methods) ? Object.keys(v.$options.methods) : [];
          trail.push({ depth: i, tag: cur.tagName, cls: (cur.className||'').toString().slice(0,80), props, data, refs, methods: methods.slice(0,30) });
        }
        cur = cur.parentElement;
      }
      return trail;
    })()
  JS

  puts "\n===== Toast UI Editor 親 Vue components ====="
  vue_info.each do |v|
    puts "depth=#{v['depth']} <#{v['tag'].downcase} class=\"#{v['cls']}\">"
    puts "  props=#{v['props'].inspect}"
    puts "  data=#{v['data'].inspect}"
    puts "  refs=#{v['refs'].inspect}"
    puts "  methods=#{v['methods'].inspect}"
  end

  browser.close
end
