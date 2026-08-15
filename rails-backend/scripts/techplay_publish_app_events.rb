# 「イベントアプリに上がってる Item」を TechPlay で公開する。
# ・TechPlay の /event 一覧を全ページ取得
# ・app の Item と (event_date + event_time) で突き合わせ
# ・複数の TechPlay イベントが同じ日時に存在する場合は ID が大きい方（新しい方）を採用、他は触らない
# ・already 公開中 はスキップ（同じものを2度公開しない）
# ・未公開（draft）→ POST /event/{id}/edit {publish_state: 'published'} で公開
# ・posting_histories.api_request_url にも保存
#
# 使い方:
#   DRY_RUN=1 で計画のみ出力
#   CONFIRM=1 で実際に公開

require 'playwright'
require 'shellwords'
require 'net/http'
require 'cgi'
require 'json'
require_relative '../config/environment'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
DRY_RUN  = ENV['DRY_RUN'] == '1' || ENV['CONFIRM'] != '1'
BASE_URL = 'https://owner.techplay.jp'

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

# ========== TechPlay の listing スクレイプ ==========
def fetch_techplay_events(page)
  events = []
  page_no = 1
  loop do
    page.goto("#{BASE_URL}/event?page=#{page_no}", waitUntil: 'domcontentloaded')
    page.wait_for_timeout(2000)
    rows = page.evaluate(<<~JS)
      (() => {
        const out = [];
        for (const r of document.querySelectorAll('table tbody tr')) {
          const tds = r.querySelectorAll('td');
          if (tds.length < 8) continue;
          out.push({
            id: (tds[0].innerText||'').trim(),
            labels: [...tds[1].querySelectorAll('.label')].map(l=>l.innerText.trim()),
            title: (tds[2].innerText||'').trim(),
            cap: (tds[4].innerText||'').trim(),
            start: (tds[6].innerText||'').trim(),
            end: (tds[7].innerText||'').trim(),
          });
        }
        return out;
      })()
    JS
    break if rows.empty?
    events.concat(rows)
    page_no += 1
    break if page_no > 10
  end
  events
end

# ========== 公開API（共通）==========
def put_event_field(page, event_id, body_hash)
  csrf_token = page.evaluate('() => { const m = document.querySelector(\'meta[name="csrf-token"]\'); return m ? m.content : null; }')
  raise 'CSRF取得失敗' unless csrf_token
  cookies = page.context.cookies.select { |c| c['domain'].to_s.include?('techplay.jp') }
  xsrf    = cookies.find { |c| c['name'] == 'XSRF-TOKEN' }
  raise 'XSRF cookie 取得失敗' unless xsrf

  uri = URI("#{BASE_URL}/event/#{event_id}/edit")
  req = Net::HTTP::Post.new(uri)
  req['Content-Type']     = 'application/json'
  req['Accept']           = 'application/json, text/plain, */*'
  req['X-Requested-With'] = 'XMLHttpRequest'
  req['X-CSRF-TOKEN']     = csrf_token
  req['X-XSRF-TOKEN']     = CGI.unescape(xsrf['value'])
  req['Cookie']           = cookies.map { |c| "#{c['name']}=#{c['value']}" }.join('; ')
  req['Origin']           = BASE_URL
  req['Referer']          = "#{BASE_URL}/event/#{event_id}/edit"
  req['User-Agent']       = 'Mozilla/5.0'
  req.body = JSON.generate(body_hash.merge('_method' => 'put'))
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |h| h.request(req) }
  [res, uri.to_s]
end

# ========== マッチング ==========
def normalize_dt(date_str, time_str)
  return nil if date_str.to_s.empty?
  d = date_str.to_s.gsub(/[年月]/, '-').gsub(/日/, '').strip
  t = time_str.to_s.strip
  t = t.empty? ? '' : "#{t.split(':').first.rjust(2,'0')}:#{(t.split(':')[1]||'00').rjust(2,'0')}"
  "#{d} #{t}".strip
end

def techplay_dt(start_str)
  # "2026-05-02 13:30:00" → "2026-05-02 13:30"
  return nil if start_str.to_s.empty?
  parts = start_str.to_s.split(' ')
  date = parts[0]
  time = parts[1].to_s[0,5]
  "#{date} #{time}"
end

# ========== Main ==========
Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox'])
  context = browser.new_context
  page    = context.new_page

  page.goto("#{BASE_URL}/auth")
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL); page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil

  tp_events = fetch_techplay_events(page)
  puts "TechPlay 取得: #{tp_events.size} 件"

  # 開催日時で grouping
  by_dt = tp_events.group_by { |e| techplay_dt(e['start']) }

  app_items = Item.where(item_type: 'event').where.not(event_date: nil).order(:event_date, :event_time)

  plan = []
  app_items.each do |item|
    dt = normalize_dt(item.event_date.to_s, item.event_time.to_s)
    next if dt.nil? || dt.split(' ').first.to_s < Date.today.to_s   # 過去はスキップ
    matches = by_dt[dt] || []
    if matches.empty?
      plan << { item: item, action: 'NO_MATCH', tp: nil }
      next
    end

    # 既に公開中があるなら何もしない（同一公開禁止）
    public_one = matches.find { |m| m['labels'].include?('公開中') }
    if public_one
      plan << { item: item, action: 'ALREADY_PUBLISHED', tp: public_one, dups: matches - [public_one] }
      next
    end

    # 未公開のうち最新ID（最大）を採用、他は touch しない
    sorted = matches.sort_by { |m| -m['id'].to_i }
    target = sorted.first
    dups   = sorted[1..] || []
    plan << { item: item, action: 'PUBLISH', tp: target, dups: dups }
  end

  puts "\n===== 公開計画 ====="
  printf("%-12s %-18s %-22s %-9s %-10s %s\n", 'item_id', 'datetime', 'title', 'tp_id', 'action', 'dups')
  plan.each do |p|
    dt   = "#{p[:item].event_date} #{p[:item].event_time}".strip
    title= p[:item].name.to_s[0,18]
    tpid = p[:tp] && p[:tp]['id']
    dups = (p[:dups] || []).map { |d| d['id'] }.join(',')
    printf("%-12s %-18s %-22s %-9s %-10s %s\n", p[:item].id, dt, title, tpid || '-', p[:action], dups)
  end

  if DRY_RUN
    puts "\n[DRY_RUN] 計画のみ。CONFIRM=1 で実行。"
    browser.close
    exit 0
  end

  puts "\n===== 公開実行 ====="
  plan.each do |p|
    next unless p[:action] == 'PUBLISH'
    tp_id = p[:tp]['id']
    item  = p[:item]
    page.goto("#{BASE_URL}/event/#{tp_id}/edit", waitUntil: 'domcontentloaded')
    page.wait_for_timeout(2500)
    res, api_url = put_event_field(page, tp_id, 'publish_state' => 'published')
    parsed = JSON.parse(res.body) rescue {}
    state  = parsed['publish_state'].to_s
    ok     = res.is_a?(Net::HTTPSuccess) && state == 'published'
    puts "[#{item.id}] tp=#{tp_id} HTTP #{res.code} state=#{state} #{ok ? '✅' : '❌ '+res.body.to_s[0,200]}"

    # PostingHistory 更新
    pubhist = PostingHistory.where(item_id: item.id, site_name: 'techplay').order(posted_at: :desc).first
    public_url = "https://techplay.jp/event/#{tp_id}"
    attrs = {
      status: ok ? 'success' : 'error',
      event_url: pubhist&.event_url.presence || "#{BASE_URL}/event/#{tp_id}/edit",
      published: ok,
      error_message: ok ? nil : "publish API failed (HTTP #{res.code})",
      posted_at: Time.current,
      api_request_url: api_url,
    }
    if pubhist
      pubhist.update!(attrs)
    else
      PostingHistory.create!(attrs.merge(item_id: item.id, site_name: 'techplay'))
    end
    sleep 1
  end

  browser.close
end
