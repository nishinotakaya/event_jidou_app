# 直前の backfill_techplay_zoom_block.rb のバグで、TechPlay の 7 件の
# markdown_description が \uXXXX リテラル化されてしまった。それを recover する。
#
# 何が起きたか:
#   - HTML には "markdown_description":"今の仕事..." (JSON-escaped) で入っていた
#   - 旧 extract_markdown が \\u003C / \\u003E 等しか decode せず、汎用 \uXXXX を
#     literal `今` のまま返した
#   - その文字列を JSON.generate で POST → 受信側で literal 今\... が保存された
#
# 直し方:
#   1. 現在の HTML から markdown_description を JSON.parse で正しく抽出
#      （literal `今` 文字列として戻る）
#   2. \uXXXX(+ 必要なら surrogate pair) を実 Unicode 文字に変換
#   3. POST で書き戻し
#
# 実行: bundle exec rails runner rails-backend/scripts/recover_techplay_unicode_escapes.rb

require 'playwright'
require 'net/http'
require 'json'
require 'cgi'
require 'uri'

OWNER_BASE = 'https://owner.techplay.jp'.freeze
AFFECTED_EVENT_IDS = %w[994831 994416 994418 994529 994552 994580 994979].freeze

# ===== \uXXXX 復号 =====
def decode_unicode_escapes(text)
  s = text.to_s
  # 先に surrogate pair（絵文字など）を処理
  s = s.gsub(/\\u(d[89ab][0-9a-fA-F]{2})\\u(d[c-fA-F][0-9a-fA-F]{2})/i) do
    high = $1.to_i(16)
    low  = $2.to_i(16)
    [( (high - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000 )].pack('U')
  end
  # 単独 \uXXXX
  s = s.gsub(/\\u([0-9a-fA-F]{4})/) { [$1.to_i(16)].pack('U') }
  # その他のエスケープ
  s.gsub('\\n', "\n").gsub('\\r', '').gsub('\\t', "\t")
   .gsub('\\"', '"').gsub('\\/', '/').gsub('\\\\', '\\')
end

# JSON.parse 経由で markdown_description を抽出（正しい unescape）
def extract_markdown_safe(html)
  # "markdown_description": "..." の JSON フラグメントを取り出して JSON.parse
  m = html.match(/"markdown_description"\s*:\s*("(?:[^"\\]|\\.)*")/)
  return nil unless m
  JSON.parse(m[1])
rescue JSON::ParserError
  nil
end

# ===== 1) Playwright で 1 回ログイン =====
puts '--- ログイン (Playwright 1回) ---'
cookie_header = nil; csrf_token = nil; xsrf_token = nil

Playwright.create(playwright_cli_executable_path: 'npx playwright') do |pw|
  browser = pw.chromium.launch(headless: false, args: %w[--no-sandbox --disable-setuid-sandbox])
  context = browser.new_context(locale: 'ja-JP', viewport: { width: 1280, height: 900 })
  page = context.new_page
  Posting::TechplayService.new.tap do |s|
    s.instance_variable_set(:@log_callback, ->(m) { puts m })
    s.send(:ensure_login, page)
  end
  cookies = page.context.cookies.select { |c| c['domain'].to_s.include?('techplay.jp') }
  cookie_header = cookies.map { |c| "#{c['name']}=#{c['value']}" }.join('; ')
  xsrf = cookies.find { |c| c['name'] == 'XSRF-TOKEN' }
  xsrf_token = xsrf ? CGI.unescape(xsrf['value']) : nil
  csrf_token = page.evaluate('() => { const m = document.querySelector(\'meta[name="csrf-token"]\'); return m ? m.content : null; }')
  browser.close
end

raise 'CSRF/Cookie 取得失敗' unless csrf_token && cookie_header
puts "[recover] ログイン成功"
puts

# ===== 2) 各イベントを修復 =====
HEADERS = {
  'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/145.0.0.0 Safari/537.36',
  'Accept-Language' => 'ja,en-US;q=0.9,en;q=0.8',
}.freeze

def http_get(uri, cookie_header)
  req = Net::HTTP::Get.new(uri)
  HEADERS.each { |k, v| req[k] = v }
  req['Accept'] = 'text/html'
  req['Cookie'] = cookie_header
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |h| h.request(req) }
end

def http_post_json(uri, body_hash, cookie_header, csrf_token, xsrf_token, referer)
  req = Net::HTTP::Post.new(uri)
  HEADERS.each { |k, v| req[k] = v }
  req['Content-Type'] = 'application/json'
  req['Accept'] = 'application/json, text/plain, */*'
  req['X-Requested-With'] = 'XMLHttpRequest'
  req['X-CSRF-TOKEN'] = csrf_token
  req['X-XSRF-TOKEN'] = xsrf_token if xsrf_token
  req['Origin'] = OWNER_BASE
  req['Referer'] = referer
  req['Cookie'] = cookie_header
  req.body = JSON.generate(body_hash.merge('_method' => 'put'))
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |h| h.request(req) }
end

results = { recovered: [], failed: [], untouched: [] }

AFFECTED_EVENT_IDS.each_with_index do |event_id, idx|
  label = "[#{idx + 1}/#{AFFECTED_EVENT_IDS.size}] event=#{event_id}"
  edit_url = "#{OWNER_BASE}/event/#{event_id}/edit"

  begin
    res = http_get(URI(edit_url), cookie_header)
    raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    raw_md = extract_markdown_safe(res.body)
    raise 'extract failed' unless raw_md

    # \u エスケープが含まれていなければ既に正常
    if !raw_md.include?('\\u')
      puts "#{label} ⏭ 既に正常（\\u escape なし）"
      results[:untouched] << event_id
      next
    end

    decoded = decode_unicode_escapes(raw_md)
    if decoded == raw_md
      puts "#{label} ⏭ decode 効果なし → skip"
      results[:untouched] << event_id
      next
    end

    puts "#{label} 復号前 #{raw_md.bytesize}B → 復号後 #{decoded.bytesize}B"
    puts "  before head: #{raw_md[0, 80].inspect}"
    puts "  after  head: #{decoded[0, 80].inspect}"

    res2 = http_post_json(URI(edit_url), { 'markdown_description' => decoded }, cookie_header, csrf_token, xsrf_token, edit_url)
    if res2.is_a?(Net::HTTPSuccess)
      puts "#{label} ✅ 復元 POST 成功"
      results[:recovered] << event_id
    else
      raise "POST HTTP #{res2.code}: #{res2.body.to_s[0, 150]}"
    end
  rescue => e
    puts "#{label} ❌ #{e.class}: #{e.message[0, 120]}"
    results[:failed] << { event_id: event_id, reason: e.message[0, 120] }
  end
end

puts
puts '=== サマリー ==='
puts "復元: #{results[:recovered].size}"; results[:recovered].each { |e| puts "  ✅ #{e}" }
puts "変更なし: #{results[:untouched].size}"; results[:untouched].each { |e| puts "  ⏭ #{e}" }
puts "失敗: #{results[:failed].size}"; results[:failed].each { |x| puts "  ❌ #{x[:event_id]} #{x[:reason]}" }
