require 'playwright'
require 'shellwords'
require 'json'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '995222')
TEST_BODY = "[probe-#{Time.now.to_i}] 解析用本文。\n\n## 見出し\n- リスト1\n- リスト2"

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
  page.on('response', ->(r) { records << { phase: @phase, dir: 'res', status: r.status, url: r.url, content_type: r.headers['content-type'] } })

  @phase = 'login'
  page.goto('https://owner.techplay.jp/auth')
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  @phase = 'goto_edit'
  page.goto("https://owner.techplay.jp/event/#{EVENT_ID}/edit", waitUntil: 'domcontentloaded')
  page.wait_for_timeout(3500)

  # ===== 詳細セクションの component を取得し $data.input を吐き出す =====
  inspect = page.evaluate(<<~JS)
    (() => {
      const wrappers = [...document.querySelectorAll('.toastui-editor-defaultUI')];
      const ed = wrappers[wrappers.length - 1];
      let cur = ed; let component = null;
      for (let i = 0; i < 25 && cur; i++) {
        const v = cur.__vue__;
        if (v && typeof v.putEvent === 'function') { component = v; break; }
        cur = cur.parentElement;
      }
      if (!component) return { found: false };
      // $data.input の構造を JSON serialize（循環参照に注意 → keys のみ）
      const inp = component.input || {};
      const dump = {};
      for (const k of Object.keys(inp)) {
        const v = inp[k];
        const t = typeof v;
        if (t === 'object' && v !== null) {
          dump[k] = '[' + (Array.isArray(v) ? 'array' : 'object') + ']';
        } else {
          dump[k] = (typeof v === 'string') ? v.slice(0, 80) : v;
        }
      }
      return { found: true, input_keys: Object.keys(inp), input_dump: dump };
    })()
  JS
  puts '===== 詳細セクション component.input ====='
  puts JSON.pretty_generate(inspect)

  # ===== input.markdown 系のキーに本文を入れて putEvent を直接呼ぶ =====
  records.clear
  @phase = 'put_event'
  put_result = page.evaluate(<<~JS, arg: TEST_BODY)
    (text) => {
      const wrappers = [...document.querySelectorAll('.toastui-editor-defaultUI')];
      const ed = wrappers[wrappers.length - 1];
      let cur = ed; let component = null;
      for (let i = 0; i < 25 && cur; i++) {
        const v = cur.__vue__;
        if (v && typeof v.putEvent === 'function') { component = v; break; }
        cur = cur.parentElement;
      }
      if (!component) return { ok: false, reason: 'no component' };

      // editor 自身も取得（refs.markdown の親が Toast UI Editor wrapper）
      const ref = component.$refs && component.$refs.markdown;
      if (ref && typeof ref.setMarkdown === 'function') {
        ref.setMarkdown(text);
      } else if (ref && ref.invoke) {
        ref.invoke('setMarkdown', text);
      }
      // input オブジェクトに直接書く（キー名が分からないので markdown / description / detail / body 全部試す）
      const inp = component.input;
      const tried = [];
      ['markdown', 'description', 'detail', 'body', 'content', 'event_description'].forEach(k => {
        if (k in inp) { inp[k] = text; tried.push(k); }
      });

      try {
        component.putEvent();
        return { ok: true, tried_keys: tried, input_after: Object.keys(inp) };
      } catch (e) {
        return { ok: false, reason: 'putEvent threw: ' + e.message, tried_keys: tried };
      }
    }
  JS
  puts "\n===== putEvent 呼び出し結果 ====="
  puts JSON.pretty_generate(put_result)

  page.wait_for_timeout(5000)
  browser.close
end

# ===== HTTP 出力 =====
def safe_dump(s)
  s = s.dup.force_encoding('UTF-8')
  s.valid_encoding? ? s : "[binary]"
end

puts "\n===== put_event フェーズの HTTP =====\n"
records.each do |r|
  next if r[:dir] == 'res'
  next if r[:method] == 'GET'
  next if r[:url] =~ /google|clarity|gtm/
  puts "#{r[:method]} #{r[:url]}"
  puts "  Content-Type req: #{r[:headers] && r[:headers]['content-type']}"
  if r[:post_data]
    body = r[:post_data].to_s
    puts "  payload(#{body.bytesize}B): #{safe_dump(body)[0, 1500]}"
  end
  puts ''
end
puts "\n----- レスポンス -----\n"
records.each do |r|
  next unless r[:dir] == 'res'
  next if r[:url] =~ /google|clarity|gtm/
  puts "  #{r[:status]} #{r[:url]} (#{r[:content_type]})"
end
