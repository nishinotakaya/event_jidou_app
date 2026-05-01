# EventRegist の新規イベント作成を実機で確認するスクリプト。
#
# 前提:
#   1. `node scripts/dump-eventregist-fields.mjs` を先に実行して
#      eventregist-cookies.json を作っておく（Google ログイン済み Cookie）
#   2. 環境変数 API2CAPTCHA_KEY を .env に設定済み
#
# 実行:
#   bundle exec rails runner rails-backend/scripts/test_eventregist_create.rb
#
# 動作:
#   - Cookie を Playwright Context にロード
#   - Posting::EventregistService#call を呼んで下書き作成
#   - 作成後の URL を表示。下書きで残るので EventRegist UI で削除する。
#
# 注意:
#   - publishSites['EventRegist'] は **false** にしているので公開はされない
#   - reCAPTCHA が出た場合は 2Captcha が解決する（API キー必須）

require 'json'
require 'date'
require 'playwright'

cookies_path = Rails.root.join('..', 'eventregist-cookies.json').to_s
unless File.exist?(cookies_path)
  abort "[テスト] Cookie ファイルが見つかりません: #{cookies_path}\n  先に node scripts/dump-eventregist-fields.mjs を実行してください"
end

cookies = JSON.parse(File.read(cookies_path)).map do |c|
  out = { name: c['name'], value: c['value'], domain: c['domain'], path: c['path'] || '/' }
  out[:expires] = c['expires'] if c['expires']
  out[:httpOnly] = c['httpOnly'] if c.key?('httpOnly')
  out[:secure] = c['secure'] if c.key?('secure')
  out[:sameSite] = c['sameSite'].to_s.capitalize if c['sameSite']
  out
end

content = <<~MD
  [EventRegist 投稿テスト #{Time.now.to_i}]

  これは EventregistService の動作確認用の下書きイベントです。
  公開はされず、後で UI から削除してください。

  - 動作確認1: ログイン状態が Cookie で復元されること
  - 動作確認2: フォームが順に入力されて下書き保存できること
  - 動作確認3: reCAPTCHA が出た場合に 2Captcha で突破できること
MD

ef = {
  'title'         => "【テスト】EventRegist 自動投稿チェック #{Date.today}",
  'startDate'     => (Date.today + 30).strftime('%Y-%m-%d'),
  'startTime'     => '19:00',
  'endDate'       => (Date.today + 30).strftime('%Y-%m-%d'),
  'endTime'       => '21:00',
  'place'         => 'オンライン',
  'capacity'      => '20',
  'zoomUrl'       => 'https://example.com/zoom-test',
  'publishSites'  => { 'EventRegist' => false } # 下書きで止める
}

Playwright.create(playwright_cli_executable_path: 'npx playwright') do |pw|
  browser = pw.chromium.launch(
    headless: false,
    args: %w[--no-sandbox --disable-setuid-sandbox --disable-blink-features=AutomationControlled],
  )
  context = browser.new_context(
    locale: 'ja-JP',
    viewport: { width: 1280, height: 900 },
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
  )
  context.add_cookies(cookies)
  page = context.new_page

  result_url = nil
  Posting::EventregistService.new.call(page, content, ef) { |msg| puts msg }
  result_url = page.url
  puts "[テスト] 結果 URL: #{result_url}"

  page.wait_for_timeout(5000)
  browser.close
end
