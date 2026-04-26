require 'playwright'
require 'json'
require 'shellwords'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
TITLE    = "[probe-#{Time.now.to_i}] 解析用テストイベント（後で削除）"
START_AT = (Time.now + 30 * 86400).strftime('%Y/%m/%d 19:00')
END_AT   = (Time.now + 30 * 86400).strftime('%Y/%m/%d 21:00')

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

records = []
@phase = 'init'

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'])
  context = browser.new_context(userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36')
  page = context.new_page

  page.on('request',  ->(r) { records << { phase: @phase, dir: 'req', method: r.method, url: r.url, post_data: r.post_data, headers: r.headers } })
  page.on('response', ->(r) { records << { phase: @phase, dir: 'res', status: r.status, url: r.url, content_type: r.headers['content-type'] } })

  # ===== 1. ログイン =====
  @phase = 'login'
  puts '[1/5] ログイン中...'
  page.goto('https://owner.techplay.jp/auth', waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL)
  page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
  if page.url.include?('select_menu')
    page.goto('https://owner.techplay.jp/dashboard', waitUntil: 'domcontentloaded') rescue nil
  end

  # ===== 2. /event/create =====
  @phase = 'goto_create'
  puts '[2/5] /event/create へ'
  page.goto('https://owner.techplay.jp/event/create', waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_selector('input#title', timeout: 30_000)
  page.wait_for_timeout(2000)

  # ===== 3. フォーム入力 =====
  @phase = 'fill_form'
  puts '[3/5] フォーム入力'
  page.fill('input#title', TITLE)

  # 開催日時 (Vue datetimepicker)
  page.evaluate(<<~JS, arg: { sel: 'input#v-datetimepicker-start', value: START_AT })
    ({ sel, value }) => {
      const el = document.querySelector(sel);
      if (!el) return null;
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      setter.call(el, value);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      el.dispatchEvent(new Event('blur', { bubbles: true }));
    }
  JS
  page.evaluate(<<~JS, arg: { sel: 'input#v-datetimepicker-end', value: END_AT })
    ({ sel, value }) => {
      const el = document.querySelector(sel);
      if (!el) return null;
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      setter.call(el, value);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      el.dispatchEvent(new Event('blur', { bubbles: true }));
    }
  JS
  page.keyboard.press('Escape') rescue nil

  # オンライン
  online_cb = page.locator('input[name="area_types[]"][value*="online"], input[name="area_types[]"]').first
  online_cb.check rescue nil

  # 参加枠 / 定員
  page.fill('input[name="attendTypes[0][name]"]', '一般枠')
  page.fill('input[name="attendTypes[0][capacity]"]', '20')

  page.wait_for_timeout(1500)

  # ===== 4. 保存（POST /event をキャプチャ） =====
  records.clear
  @phase = 'save_create'
  puts '[4/5] 保存ボタンクリック → POST /event をキャプチャ'
  save_btn = page.locator('button[type="submit"]:has-text("保存")').first
  save_btn.click
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
  page.wait_for_timeout(3000)

  created_url = page.url
  puts "    -> #{created_url}"
  event_id = created_url[%r{/event/(\d+)}, 1]

  # ===== 5. 編集ページに遷移して、Toast UI Editor に本文を入力して別フィールドを更新→保存を試行 =====
  if event_id
    puts "[5/5] 作成された event_id=#{event_id} の編集ページで本文反映を試行"
    # 一旦、ここでは追加観察はせず、削除を試す（テストイベントなので後始末）。
    # 削除UIの場所が不明なので、まず /event/:id/edit に遷移して「削除」相当のリクエストも探す。
    @phase = 'goto_edit'
    page.goto("https://owner.techplay.jp/event/#{event_id}/edit", waitUntil: 'domcontentloaded') rescue nil
    page.wait_for_timeout(3000)
  end

  browser.close
end

# ===== 結果出力 =====
def safe_dump(obj)
  case obj
  when String
    s = obj.dup.force_encoding('UTF-8')
    s.valid_encoding? ? s : "[binary #{obj.bytesize}B]"
  when Hash  then obj.transform_values { |v| safe_dump(v) }
  when Array then obj.map { |v| safe_dump(v) }
  else obj
  end
end
File.write('/tmp/techplay_create_records.json', JSON.pretty_generate(safe_dump(records)))

puts "\n===== save_create フェーズで飛んだ HTTP =====\n"
records.each do |r|
  next if r[:dir] == 'res'
  next if r[:method] == 'GET'
  puts "#{r[:method]} #{r[:url]}"
  puts "  Content-Type: #{r[:headers] && r[:headers]['content-type']}"
  if r[:post_data]
    body = r[:post_data].to_s
    body_utf = body.dup.force_encoding('UTF-8')
    body_show = body_utf.valid_encoding? ? body_utf : "[binary #{body.bytesize}B]"
    puts "  payload(#{body.bytesize}B): #{body_show[0, 1500]}"
  end
  puts ''
end

puts "\n===== save_create フェーズの HTTP レスポンス =====\n"
records.each do |r|
  next unless r[:dir] == 'res'
  puts "  #{r[:status]} #{r[:url]}"
end

puts "\n全レコード: /tmp/techplay_create_records.json (#{records.length} 件)"
