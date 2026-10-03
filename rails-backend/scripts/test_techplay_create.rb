# TechPlay 新規投稿の本文反映を実機テストするスクリプト。
# 1. Playwright 起動 → ログイン
# 2. Posting::TechplayService#call で新規イベント作成 (publish=false で下書き)
# 3. 作成された event_id の本文を curl で getMarkdown して空でないことを確認
# 4. テストイベントは下書き状態で残るので、後で TechPlay UI で削除

require 'playwright'
require 'shellwords'
require 'date'

content = <<~MD
  [TechPlay 新規投稿テスト #{Time.now.to_i}]

  ## このイベントの目的

  Curl 化された fill_description_via_api が新規投稿時に
  ちゃんと本文を保存できるかを確認するためのテストイベントです。

  - 確認1: 本文が編集ページに反映される
  - 確認2: techplay:smoke で getMarkdown が空でないことを検証できる

  ※ 公開せず下書き保存のみ。後で削除します。
MD

ef = {
  'startDate'    => (Date.today + 30).strftime('%Y-%m-%d'),
  'startTime'    => '19:00',
  'endDate'      => (Date.today + 30).strftime('%Y-%m-%d'),
  'endTime'      => '21:00',
  'place'        => 'オンライン',
  'capacity'     => 20,
  'publishSites' => { 'TechPlay' => false },
}

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

result_url = nil
Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'])
  context = browser.new_context
  page = context.new_page

  service = Posting::TechplayService.new
  service.call(page, content, ef) { |msg| puts msg }

  result_url = page.url
  browser.close
end

puts "\n=== Final URL: #{result_url}"
event_id = result_url[%r{/event/(\d+)}, 1]
abort '❌ event_id を取得できなかった' unless event_id
puts "=== event_id: #{event_id}"

# smoke 実行
puts "\n=== Running techplay:smoke[#{event_id}]"
Rake.application.init
Rake.application.load_rakefile
Rake::Task["techplay:smoke"].invoke(event_id)
