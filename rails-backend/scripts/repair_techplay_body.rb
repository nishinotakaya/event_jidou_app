# TechPlay の指定イベントの「詳細欄」だけを curl(Net::HTTP) で書き換えるスクリプト。
# Playwright で session を取得 → そこから cookies と CSRF を取り出して、純粋な curl で本文を PUT する。
#
# 使い方:
#   PROBE_EVENT_ID=994979 BODY_FROM=item_id_or_file bundle exec rails runner scripts/repair_techplay_body.rb
#
# 安全弁: --dry-run で payload と URL だけ表示して送信しない

require 'playwright'
require 'shellwords'
require 'net/http'
require 'json'
require 'uri'
require 'cgi'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '995222')
DRY_RUN  = ENV['DRY_RUN'] == '1'

# 本文ソース: BODY_FILE > ITEM_ID > 固定文字列 の優先度
BODY = if ENV['BODY_FILE']
  File.read(ENV['BODY_FILE'])
elsif ENV['ITEM_ID']
  item = Item.find_by(id: ENV['ITEM_ID'])
  raise "Item not found: #{ENV['ITEM_ID']}" unless item
  item.content.to_s
else
  "[probe-#{Time.now.to_i}] curl 経由で書き込まれた詳細欄テスト本文。\n\n## 見出し\n- リスト1\n- リスト2\n\n本文反映の動作確認用。"
end

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

cookies_arr = nil
csrf_token  = nil

# ===== Step 1: Playwright でログイン → cookies + CSRF を取得 =====
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
  page.wait_for_timeout(3000)

  csrf_token = page.evaluate('() => { const m = document.querySelector(\'meta[name="csrf-token"]\'); return m ? m.content : (window.Laravel && window.Laravel.csrfToken) || null; }')
  cookies_arr = context.cookies.select { |c| c['domain'].include?('techplay.jp') }

  browser.close
end

raise 'CSRF token 取得失敗' unless csrf_token
puts "[OK] CSRF token: #{csrf_token[0,12]}... (#{csrf_token.length} chars)"
puts "[OK] cookies: #{cookies_arr.map { |c| c['name'] }.inspect}"

# ===== Step 2: Net::HTTP で詳細欄を PUT =====
xsrf_cookie = cookies_arr.find { |c| c['name'] == 'XSRF-TOKEN' }
raise 'XSRF-TOKEN cookie 見つからず' unless xsrf_cookie
xsrf_header_value = CGI.unescape(xsrf_cookie['value'])
cookie_header = cookies_arr.map { |c| "#{c['name']}=#{c['value']}" }.join('; ')

uri = URI("https://owner.techplay.jp/event/#{EVENT_ID}/edit")
req = Net::HTTP::Post.new(uri)
req['Content-Type']   = 'application/json'
req['Accept']         = 'application/json, text/plain, */*'
req['X-Requested-With'] = 'XMLHttpRequest'
req['X-CSRF-TOKEN']   = csrf_token
req['X-XSRF-TOKEN']   = xsrf_header_value
req['Cookie']         = cookie_header
req['Origin']         = 'https://owner.techplay.jp'
req['Referer']        = "https://owner.techplay.jp/event/#{EVENT_ID}/edit"
req['User-Agent']     = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'

payload = { 'markdown_description' => BODY, '_method' => 'put' }
req.body = JSON.generate(payload)

puts "\n===== PUT request ====="
puts "URL:  #{uri}"
puts "Body keys: #{payload.keys.inspect}, body bytesize: #{req.body.bytesize}"
puts "Body head: #{BODY[0,120].inspect}"

if DRY_RUN
  puts "\n[DRY_RUN] 送信せずに終了"
  exit
end

res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(req) }
puts "\n===== Response ====="
puts "Status: #{res.code} #{res.message}"
puts "Content-Type: #{res['content-type']}"
puts "Body head: #{res.body.to_s[0, 400]}"

# ===== Step 3: 反映確認（GET edit ページから markdown_description を取り直す） =====
verify_uri = URI("https://owner.techplay.jp/event/#{EVENT_ID}/edit")
verify_req = Net::HTTP::Get.new(verify_uri)
verify_req['Cookie']     = cookie_header
verify_req['User-Agent'] = req['User-Agent']
verify_res = Net::HTTP.start(verify_uri.host, verify_uri.port, use_ssl: true) { |http| http.request(verify_req) }
hit = verify_res.body.include?(BODY[0, 30])
puts "\n===== Verify ====="
puts "GET status: #{verify_res.code}"
puts "本文先頭30文字が edit ページに含まれるか: #{hit ? '✅ YES' : '❌ NO'}"
