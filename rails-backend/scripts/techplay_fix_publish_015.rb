# event_015 (TechPlay 994831) の本文をAPIで設定してから公開する
require 'playwright'
require 'shellwords'
require 'net/http'
require 'cgi'
require 'json'
require_relative '../config/environment'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
TP_ID    = ENV.fetch('TP_ID', '994831')
ITEM_ID  = ENV.fetch('ITEM_ID', 'event_015')
BASE_URL = 'https://owner.techplay.jp'

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

def put_field(page, event_id, body_hash)
  csrf = page.evaluate('() => { const m = document.querySelector(\'meta[name="csrf-token"]\'); return m ? m.content : null; }')
  cookies = page.context.cookies.select { |c| c['domain'].to_s.include?('techplay.jp') }
  xsrf    = cookies.find { |c| c['name'] == 'XSRF-TOKEN' }
  uri = URI("#{BASE_URL}/event/#{event_id}/edit")
  req = Net::HTTP::Post.new(uri)
  req['Content-Type']     = 'application/json'
  req['Accept']           = 'application/json, text/plain, */*'
  req['X-Requested-With'] = 'XMLHttpRequest'
  req['X-CSRF-TOKEN']     = csrf
  req['X-XSRF-TOKEN']     = CGI.unescape(xsrf['value'])
  req['Cookie']           = cookies.map { |c| "#{c['name']}=#{c['value']}" }.join('; ')
  req['Origin']           = BASE_URL
  req['Referer']          = "#{BASE_URL}/event/#{event_id}/edit"
  req['User-Agent']       = 'Mozilla/5.0'
  req.body = JSON.generate(body_hash.merge('_method' => 'put'))
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |h| h.request(req) }
  [res, uri.to_s]
end

item = Item.find(ITEM_ID)
body = item.content.to_s

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox'])
  context = browser.new_context
  page    = context.new_page

  page.goto("#{BASE_URL}/auth")
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  page.goto("#{BASE_URL}/event/#{TP_ID}/edit", waitUntil: 'domcontentloaded')
  page.wait_for_timeout(3000)

  # 1. 本文セット
  res, api1 = put_field(page, TP_ID, 'markdown_description' => body)
  puts "[本文] HTTP #{res.code} api=#{api1}"
  puts "  body: #{(JSON.parse(res.body) rescue {})['markdown_description'].to_s[0,80]}"

  # 2. 公開
  res, api2 = put_field(page, TP_ID, 'publish_state' => 'published')
  puts "[公開] HTTP #{res.code} api=#{api2}"
  parsed = JSON.parse(res.body) rescue {}
  state  = parsed['publish_state'].to_s
  ok     = res.is_a?(Net::HTTPSuccess) && state == 'published'

  if ok
    public_url = "https://techplay.jp/event/#{TP_ID}"
    edit_url   = "#{BASE_URL}/event/#{TP_ID}/edit"
    h = PostingHistory.where(item_id: ITEM_ID, site_name: 'techplay').order(posted_at: :desc).first
    attrs = {
      status: 'success', event_url: public_url, published: true,
      error_message: nil, posted_at: Time.current, api_request_url: api2,
    }
    h ? h.update!(attrs) : PostingHistory.create!(attrs.merge(item_id: ITEM_ID, site_name: 'techplay'))
    puts "✅ #{ITEM_ID} → #{public_url}"
  else
    puts "❌ 公開失敗: #{res.body.to_s[0,300]}"
  end

  browser.close
end
