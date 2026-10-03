# 既存 TechPlay 投稿の説明文末尾に Zoom URL ブロックを一括追加。
#
# ハイブリッド方式（耐ネットワーク不安定）:
#   1. Playwright で /auth に 1 回だけログイン（CSRF + Cookie 取得）
#   2. 以降は Net::HTTP のみで:
#        GET /event/{id}/edit  → HTML から markdown_description を抽出
#        Append Zoom block
#        POST /event/{id}/edit (JSON, _method=put)  → 説明文を上書き
#   3. ネットワーク瞬断時は per-event リトライ (3回)
#
# 実行: bundle exec rails runner rails-backend/scripts/backfill_techplay_zoom_block.rb

require 'playwright'
require 'net/http'
require 'json'
require 'cgi'
require 'uri'

OWNER_BASE = 'https://owner.techplay.jp'.freeze

histories = PostingHistory
  .where(site_name: 'techplay', status: 'success')
  .where.not(event_url: [nil, '', 'about:blank'])
  .order(:created_at)

targets = histories.map do |h|
  item = h.item_id ? Item.find_by(id: h.item_id) : nil
  zoom_url = item&.zoom_url.to_s.strip
  event_id = h.event_url.to_s[/event\/(\d+)/, 1]
  next nil if event_id.nil?
  { history_id: h.id, item_id: h.item_id, event_id: event_id, zoom_url: zoom_url }
end.compact

puts "=== 対象 #{targets.size} 件（zoom_url 空は skip）==="
update_targets = targets.reject { |t| t[:zoom_url].empty? }
skip_targets   = targets.select { |t| t[:zoom_url].empty? }
puts "→ update=#{update_targets.size}, skip=#{skip_targets.size}"
puts

# ===== 1) Playwright でログインして Cookie + CSRF を取得 =====
puts '--- ログイン (Playwright 1回) ---'
cookie_header = nil
csrf_token = nil
xsrf_token = nil

Playwright.create(playwright_cli_executable_path: 'npx playwright') do |pw|
  browser = pw.chromium.launch(
    headless: false,
    args: %w[--no-sandbox --disable-setuid-sandbox --disable-blink-features=AutomationControlled],
  )
  context = browser.new_context(locale: 'ja-JP', viewport: { width: 1280, height: 900 })
  page = context.new_page

  svc = Posting::TechplayService.new
  svc.instance_variable_set(:@log_callback, ->(m) { puts m })
  svc.send(:ensure_login, page)

  cookies = page.context.cookies.select { |c| c['domain'].to_s.include?('techplay.jp') }
  cookie_header = cookies.map { |c| "#{c['name']}=#{c['value']}" }.join('; ')
  xsrf = cookies.find { |c| c['name'] == 'XSRF-TOKEN' }
  xsrf_token = xsrf ? CGI.unescape(xsrf['value']) : nil
  csrf_token = page.evaluate('() => { const m = document.querySelector(\'meta[name="csrf-token"]\'); return m ? m.content : null; }')

  browser.close
end

raise '[backfill] CSRF/Cookie 取得失敗' unless csrf_token && cookie_header
puts "[backfill] cookies=#{cookie_header.length} chars  csrf=#{csrf_token[0, 20]}..."
puts

# ===== Net::HTTP ヘルパ =====
HEADERS = {
  'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
  'Accept-Language' => 'ja,en-US;q=0.9,en;q=0.8',
}.freeze

def http_get(uri, cookie_header, headers = {})
  req = Net::HTTP::Get.new(uri)
  HEADERS.each { |k, v| req[k] = v }
  headers.each { |k, v| req[k] = v }
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

# HTML から markdown_description の値を抽出する。
# TechPlay の編集ページは Vue 系で、データが <script> の中の JS リテラルに埋め込まれている。
# 想定パターン:
#   "markdown_description":"...."   （JSON）
#   markdown_description: "..."     （JS object）
#   <textarea name="markdown_description">....</textarea>
def extract_markdown(html)
  return nil unless html

  # 1) JSON 形式（最も汎用）: \"markdown_description\":\"...\" or "markdown_description":"..."
  m = html.match(/"markdown_description"\s*:\s*"((?:[^"\\]|\\.)*)"/)
  if m
    return m[1].gsub('\\n', "\n").gsub('\\r', '').gsub('\\"', '"').gsub('\\\\', '\\').gsub('\\u003C', '<').gsub('\\u003E', '>').gsub('\\/', '/')
  end

  # 2) <textarea> 直接埋め込み
  m = html.match(/<textarea[^>]*name=["']markdown_description["'][^>]*>([\s\S]*?)<\/textarea>/i)
  return CGI.unescapeHTML(m[1]) if m

  nil
end

def append_zoom_text(body_text, zoom_url)
  return body_text if body_text.to_s.include?(zoom_url)
  block = [
    '【オンライン参加について】',
    '本イベントは Zoom にて開催します。お時間になりましたら下記 URL よりご入室ください。',
    '',
    "Zoom URL: #{zoom_url}",
  ].join("\n")
  "#{body_text.to_s.rstrip}\n\n#{block}\n"
end

# ===== 2) 各イベントを Net::HTTP で更新 =====
results = { updated: [], skipped: [], failed: [] }

targets.each_with_index do |t, idx|
  label = "[#{idx + 1}/#{targets.size}] event=#{t[:event_id]}"
  if t[:zoom_url].empty?
    puts "#{label} ⏭ zoom_url が空 → skip"
    results[:skipped] << t
    next
  end

  edit_url = "#{OWNER_BASE}/event/#{t[:event_id]}/edit"

  # GET HTML（リトライ 3 回）
  body_text = nil
  3.times do |attempt|
    begin
      uri = URI(edit_url)
      res = http_get(uri, cookie_header, 'Accept' => 'text/html,application/xhtml+xml')
      if res.code == '302' || res.code == '301'
        puts "#{label} ⚠ HTML #{res.code} → #{res['Location']} (auth 切れ?) → skip"
        results[:failed] << t.merge(reason: "auth #{res.code}")
        body_text = :skip
        break
      elsif res.is_a?(Net::HTTPSuccess)
        body_text = extract_markdown(res.body)
        break
      else
        puts "#{label} ⚠ HTML HTTP #{res.code} (attempt #{attempt + 1}) → retry"
        sleep 2
      end
    rescue => e
      puts "#{label} ⚠ HTML 取得失敗 (attempt #{attempt + 1}): #{e.class}: #{e.message[0, 80]}"
      sleep 3
    end
  end

  next if body_text == :skip

  unless body_text
    puts "#{label} ❌ markdown_description 抽出失敗 → skip"
    results[:failed] << t.merge(reason: 'extract markdown failed')
    next
  end

  if body_text.include?(t[:zoom_url])
    puts "#{label} ⏭ 既に Zoom URL あり → skip（冪等）"
    results[:skipped] << t
    next
  end

  appended = append_zoom_text(body_text, t[:zoom_url])

  # POST update（リトライ 3 回）
  saved = false
  3.times do |attempt|
    begin
      uri = URI(edit_url)
      res = http_post_json(uri, { 'markdown_description' => appended }, cookie_header, csrf_token, xsrf_token, edit_url)
      if res.is_a?(Net::HTTPSuccess)
        saved = true
        break
      else
        puts "#{label} ⚠ POST HTTP #{res.code} (attempt #{attempt + 1}): #{res.body.to_s[0, 200]}"
        sleep 3
      end
    rescue => e
      puts "#{label} ⚠ POST 失敗 (attempt #{attempt + 1}): #{e.class}: #{e.message[0, 80]}"
      sleep 3
    end
  end

  if saved
    puts "#{label} ✅ Zoom ブロック追記完了 (元 #{body_text.bytesize}B → #{appended.bytesize}B)"
    results[:updated] << t
  else
    puts "#{label} ❌ POST 失敗 (3回)"
    results[:failed] << t.merge(reason: 'POST failed 3x')
  end
end

puts
puts "=== サマリー ==="
puts "更新: #{results[:updated].size}"
results[:updated].each { |t| puts "  ✅ event=#{t[:event_id]} item=#{t[:item_id]}" }
puts "スキップ: #{results[:skipped].size}"
results[:skipped].each { |t| puts "  ⏭ event=#{t[:event_id]} item=#{t[:item_id]}" }
puts "失敗: #{results[:failed].size}"
results[:failed].each { |t| puts "  ❌ event=#{t[:event_id]} reason=#{t[:reason]}" }
