# TechPlay event/995308 を実機で確認:
#   1) 公開ページの「説明」セクションに Zoom ブロックが表示されてるか
#   2) Owner 編集ページで markdown_description の保存値（API GET 経由で確実に取る）
#   3) 参加者一覧（/event/{id}/attendee）

require 'playwright'
require 'json'
require 'net/http'
require 'cgi'

EVENT_ID = '995308'.freeze
PUBLIC_URL    = "https://techplay.jp/event/#{EVENT_ID}".freeze
EDIT_URL      = "https://owner.techplay.jp/event/#{EVENT_ID}/edit".freeze
ATTENDEE_URL  = "https://owner.techplay.jp/event/#{EVENT_ID}/attendee".freeze

Playwright.create(playwright_cli_executable_path: 'npx playwright') do |pw|
  browser = pw.chromium.launch(
    headless: false,
    args: %w[--no-sandbox --disable-setuid-sandbox --disable-blink-features=AutomationControlled],
  )
  context = browser.new_context(
    locale: 'ja-JP',
    viewport: { width: 1280, height: 900 },
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
  )

  conn = ServiceConnection.find_by(service_name: 'techplay')
  if conn&.session_data.present?
    state = JSON.parse(conn.session_data) rescue nil
    context.add_cookies(state['cookies']) if state && state['cookies']
  end

  page = context.new_page

  # 先に Owner にログインしておく（cookie 切れ対策）
  svc = Posting::TechplayService.new
  svc.instance_variable_set(:@log_callback, ->(m) { puts m })
  svc.send(:ensure_login, page)

  # ---------- A) 公開ページの説明セクション ----------
  puts '=' * 60
  puts "A) 公開ページ #{PUBLIC_URL}"
  puts '=' * 60
  page.goto(PUBLIC_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_timeout(3500)

  visible = page.evaluate(<<~'JS')
    (() => {
      const sels = [
        '.event-detail__description',
        '.event-description',
        '.description',
        'section[class*="description"]',
        'div[class*="Description"]',
        'div[class*="description"]',
        '[id*="description"]',
        'main',
      ];
      let best = null;
      for (const s of sels) {
        const els = document.querySelectorAll(s);
        for (const el of els) {
          const t = el.innerText || '';
          if (t.length > 200 && (!best || t.length > best.text.length)) best = { selector: s, text: t };
        }
      }
      // h2/h3 の「説明」「概要」「イベント詳細」直下を取得するフォールバック
      if (!best) {
        const heads = [...document.querySelectorAll('h1,h2,h3')];
        for (const h of heads) {
          if (/説明|概要|詳細/.test(h.innerText)) {
            const next = h.parentElement?.parentElement?.innerText || h.parentElement?.innerText || '';
            if (next.length > 200) { best = { selector: 'h*-parent', text: next }; break; }
          }
        }
      }
      return best || { selector: 'none', text: document.body.innerText };
    })()
  JS

  text = visible['text'].to_s
  puts "セレクタ: #{visible['selector']}"
  puts "全長: #{text.bytesize} bytes"
  puts "Zoom URL を含む?      #{text.include?('us02web.zoom.us') ? '✅ YES' : '❌ NO'}"
  puts "「オンライン参加について」を含む? #{text.include?('オンライン参加について') ? '✅ YES' : '❌ NO'}"
  puts "「ミーティングID」を含む? #{text.include?('ミーティングID') ? '✅ YES' : '❌ NO'}"
  puts "末尾 800 文字 ----"
  puts text[-800..] || text
  puts "---- 末尾終わり"
  puts

  # ---------- B) Owner 編集ページの保存値（GET API 経由）----------
  puts '=' * 60
  puts "B) Owner 編集ページ #{EDIT_URL}"
  puts '=' * 60
  page.goto(EDIT_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_timeout(3500)

  # Toast UI Editor / Vue/React コンポーネント込みで markdown を取りに行く
  api_md = page.evaluate(<<~'JS')
    (() => {
      // window.__INITIAL_STATE__ や window.__NEXT_DATA__ に description が居るパターン
      const sources = [];
      try { if (window.__INITIAL_STATE__) sources.push(['__INITIAL_STATE__', JSON.stringify(window.__INITIAL_STATE__)]); } catch (e) {}
      try { if (window.__NEXT_DATA__) sources.push(['__NEXT_DATA__', JSON.stringify(window.__NEXT_DATA__)]); } catch (e) {}
      // dataset / hidden input
      const inp = document.querySelector('input[name="markdown_description"], textarea[name="markdown_description"]');
      if (inp && inp.value) sources.push(['hidden_input', inp.value]);
      // Toast UI editor 内 textarea
      const tuiTa = document.querySelector('.toastui-editor-md-container textarea');
      if (tuiTa && tuiTa.value) sources.push(['toastui_textarea', tuiTa.value]);
      return sources.map(([k, v]) => ({ key: k, len: v.length, head: v.slice(0, 200), hasZoom: v.includes('us02web.zoom.us') }));
    })()
  JS

  api_md.to_a.each do |src|
    puts "[B-#{src['key']}] len=#{src['len']} hasZoom=#{src['hasZoom']} head=#{src['head'].inspect[0, 200]}"
  end

  # API で実値を取得（GET /event/:id/edit を JSON で叩く）
  cookies = page.context.cookies.select { |c| c['domain'].to_s.include?('techplay.jp') }
  cookie_header = cookies.map { |c| "#{c['name']}=#{c['value']}" }.join('; ')
  csrf = page.evaluate('() => { const m = document.querySelector(\'meta[name="csrf-token"]\'); return m ? m.content : null; }')
  xsrf = cookies.find { |c| c['name'] == 'XSRF-TOKEN' }

  uri = URI("https://owner.techplay.jp/event/#{EVENT_ID}/edit")
  req = Net::HTTP::Get.new(uri)
  req['Accept'] = 'application/json, text/plain, */*'
  req['X-Requested-With'] = 'XMLHttpRequest'
  req['X-CSRF-TOKEN'] = csrf if csrf
  req['X-XSRF-TOKEN'] = CGI.unescape(xsrf['value']) if xsrf
  req['Cookie'] = cookie_header
  req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/145.0.0.0 Safari/537.36'
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  parsed = JSON.parse(res.body) rescue nil
  if parsed.is_a?(Hash)
    md = parsed['markdown_description'].to_s
    puts "[B-API] HTTP #{res.code}, markdown_description len=#{md.bytesize} hasZoom=#{md.include?('us02web.zoom.us')}"
    puts "末尾 600 文字 ----"
    puts md[-600..] || md
    puts "---- 末尾終わり"
  else
    puts "[B-API] HTTP #{res.code} (JSON でない / parse 失敗)"
    puts res.body.to_s[0, 200]
  end
  puts

  # ---------- C) 参加者リスト ----------
  puts '=' * 60
  puts "C) 参加者ページ #{ATTENDEE_URL}"
  puts '=' * 60
  page.goto(ATTENDEE_URL, waitUntil: 'domcontentloaded', timeout: 30_000) rescue nil
  page.wait_for_timeout(3500)
  puts "URL: #{page.url}"

  participants = page.evaluate(<<~'JS')
    (() => {
      const out = [];
      const rows = document.querySelectorAll('table tbody tr');
      for (const r of rows) {
        const cells = [...r.querySelectorAll('td')].map(c => c.innerText.trim()).filter(Boolean);
        if (cells.length) out.push(cells);
      }
      if (out.length) return { method: 'table', rows: out, total: rows.length };

      const cards = [...document.querySelectorAll('[class*="attendee"], [class*="participant"], li.user, li.attendee, .user-card')]
        .map(el => el.innerText.trim()).filter(t => t && t.length < 300);
      if (cards.length) return { method: 'cards', rows: cards };

      // ヘッダー候補も拾う
      const heads = [...document.querySelectorAll('h1,h2,h3,.count')].map(h => h.innerText.trim()).filter(Boolean);
      return { method: 'none', rows: [], heads, pageText: document.body.innerText.slice(0, 600) };
    })()
  JS
  puts "抽出方式: #{participants['method']}"
  puts "件数: #{Array(participants['rows']).size}"
  if participants['rows'].is_a?(Array) && participants['rows'].any?
    participants['rows'].first(50).each_with_index do |row, i|
      puts "  ##{i + 1}: #{row.is_a?(Array) ? row.join(' | ') : row}"
    end
  else
    puts "ヘッダー候補: #{participants['heads'].inspect}"
    puts "ページ先頭600文字:"
    puts participants['pageText']
  end

  page.wait_for_timeout(3000)
  browser.close
end
