# 既存 TechPlay イベント (event/995308) の説明文末尾に Zoom ブロックが
# 追加されるかを実機テスト。
#
# 動作:
#   1. ensure_login で TechPlay にログイン
#   2. /event/995308/edit に遷移
#   3. 既存 markdown_description を取得
#   4. append_zoom_block で Zoom ブロックを末尾追加
#   5. fill_description_via_api で API 経由で保存
#   6. 保存後の markdown_description を再取得して Zoom ブロックが含まれるか確認
#
# 実行:
#   bundle exec rails runner rails-backend/scripts/test_techplay_zoom_block.rb

require 'playwright'
require 'net/http'
require 'json'

EVENT_ID = '995308'.freeze
EDIT_URL = "https://owner.techplay.jp/event/#{EVENT_ID}/edit".freeze

ef = {
  'zoomUrl'      => 'https://us02web.zoom.us/j/83744196519?pwd=YwCbA8RzcqXmma5iIBYnOXELtR4oPj.1',
  'zoomId'       => '837 4419 6519',
  'zoomPasscode' => '123456',
}

playwright_path = `which npx`.strip + ' playwright'

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

  # ServiceConnection から storage_state を流し込む（あれば）
  conn = ServiceConnection.find_by(service_name: 'techplay')
  if conn&.session_data.present?
    begin
      ctx_state = JSON.parse(conn.session_data)
      context.add_cookies(ctx_state['cookies'].to_a) if ctx_state['cookies']
      puts "[テスト] DBセッション復元 (#{ctx_state['cookies']&.size || 0} cookies)"
    rescue JSON::ParserError
      puts "[テスト] セッション破損 - スキップ"
    end
  end

  page = context.new_page

  svc = Posting::TechplayService.new
  svc.instance_variable_set(:@log_callback, ->(m) { puts m })

  # 1) ログイン
  svc.send(:ensure_login, page)

  # 2) 編集ページへ
  puts "[テスト] /event/#{EVENT_ID}/edit に遷移..."
  page.goto(EDIT_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_timeout(3000)

  # 3) 既存本文を取得（DOM に出てなければスキップ。簡易確認のみ）
  current_body = page.evaluate(<<~JS) rescue ''
    (() => {
      const ta = document.querySelector('textarea[name="markdown_description"]');
      if (ta) return ta.value;
      const codes = [...document.querySelectorAll('pre, .CodeMirror-code, .toastui-editor-md-container')];
      return codes.map(c => c.textContent).join('\\n');
    })()
  JS
  puts "[テスト] 既存本文 (先頭200文字): #{current_body.to_s[0, 200].inspect}"

  # 4) append_zoom_block を呼び出し
  appended = svc.send(:append_zoom_block, current_body.to_s, ef)
  puts "[テスト] 追加後本文 (末尾200文字): #{appended[-200..].to_s.inspect}"

  if appended == current_body
    puts "[テスト] ⚠️ append_zoom_block が動かなかった（既に Zoom URL を含んでいる or zoomUrl が空）"
  else
    # 5) API で保存
    svc.send(:fill_description_via_api, page, appended)

    # 6) 再取得して確認
    page.reload(waitUntil: 'domcontentloaded', timeout: 30_000)
    page.wait_for_timeout(3000)
    saved = page.evaluate(<<~JS) rescue ''
      (() => {
        const ta = document.querySelector('textarea[name="markdown_description"]');
        return ta ? ta.value : '';
      })()
    JS
    has_zoom = saved.include?(ef['zoomUrl'])
    puts has_zoom ? "[テスト] ✅ 保存後の本文に Zoom URL を確認" : "[テスト] ⚠️ 保存後の本文に Zoom URL なし"
    puts "[テスト] 保存後本文 (末尾200文字): #{saved[-200..].to_s.inspect}"
  end

  page.wait_for_timeout(3000)
  browser.close
end
