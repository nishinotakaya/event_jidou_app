require "test_helper"

# 社会人サークルアッシュ（www.ya-7.com）。エリア一覧の HTML パースと、タイトルでのキーワード AND 絞り込み・開催中止の除外・エリア→URL 選択を検証する（HTTP は打たない）
class AshCircleServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  def service_class
    Research::AshCircleService
  end

  # フィクスチャを 1 回目の応答にする。要求された URL も返す。
  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("ash_circle") ])
    [ service.search(keyword, locations), requested_urls ]
  end

  def card_html(href: "https://www.ya-7.com/event_info.php?EventNum=1", title: "テスト", image_src: "/eventimage/a.png")
    <<~HTML
      <article class="entry"><a href="#{href}">
        <div class="event_list_title">#{title} 社会人サークルイベント</div>
        <picture><img src="#{image_src}"></picture>
        <div class="f-left_inner_three"><div>東京</div>
          <div><time datetime="2026-10-12">2026.10.12<span>（月）</span></time></div>
          <div><time datetime="2026-10-12">10:00&#xFF5E;12:00</time></div></div>
      </a></article>
    HTML
  end

  def search_html(html, keyword = "")
    service = service_class.new
    stub_http_get(service, [ html ])
    service.search(keyword)
  end

  test "SITE_KEY は ash_circle、SITE_LABEL は社会人サークルアッシュ" do
    assert_equal "ash_circle", service_class::SITE_KEY
    assert_equal "社会人サークルアッシュ", service_class::SITE_LABEL
  end

  test "開催中止のカードを除いた 2 件を取り出し、結果の形が揃っている" do
    event_results, = search_with("")

    assert_equal 2, event_results.size
    event_results.each do |event_result|
      assert_equal service_class::SITE_KEY, event_result[:site]
      assert_equal service_class::SITE_LABEL, event_result[:siteLabel]
    end
    assert_not(event_results.any? { |event_result| event_result[:title].include?("開催中止") })
  end

  test "先頭のカードを title・url・startsAt・datetimeText・address・organizer・image に割り当てる" do
    event_results, = search_with("")
    first_event = event_results.first

    assert_equal "柏市で自然な出会い５０代（アラフィフ）・６０代（アラカン）で友達＆恋人作り会｜男性・女性の友活・婚活・恋活イベント", first_event[:title]
    assert_equal "https://www.ya-7.com/event_info.php?EventNum=#{first_event[:url][/\d+\z/]}", first_event[:url]
    assert_equal "2026.10.10（土） 17:00～19:00", first_event[:datetimeText]
    assert_equal "千葉", first_event[:address]
    assert_nil first_event[:venue]
    assert_equal "社会人サークルアッシュ", first_event[:organizer]
  end

  test "startsAt は 1 つ目の日付 + 2 つ目の開始時刻を JST で組み立てる" do
    event_results, = search_with("")
    starts_at = Time.iso8601(event_results.first[:startsAt])

    assert_equal [ 2026, 10, 10, 17, 0 ], [ starts_at.year, starts_at.month, starts_at.day, starts_at.hour, starts_at.min ]
    assert_equal 9 * 3600, starts_at.utc_offset
  end

  test "相対パスの画像は絶対 URL になる" do
    event_results, = search_with("")

    assert_equal "https://www.ya-7.com/eventimage/1696168555_2091807003.jpg", event_results.first[:imageUrl]
  end

  test "href が javascript: のカードは捨てられる" do
    assert_equal [], search_html(card_html(href: "javascript:alert(1)"))
  end

  test "相対 href のカードも絶対 URL にして取れる" do
    event_results = search_html(card_html(href: "event_info.php?EventNum=7"))

    assert_equal [ "https://www.ya-7.com/event_info.php?EventNum=7" ], event_results.map { |event_result| event_result[:url] }
  end

  test "タイトルが空のカードは捨てられる" do
    assert_equal [], search_html(card_html(title: ""))
  end

  test "画像が http(s) でなければ画像だけ nil で結果は残る" do
    event_results = search_html(card_html(image_src: "javascript:alert(1)"))

    assert_equal 1, event_results.size
    assert_nil event_results.first[:imageUrl]
  end

  test "キーワードは空白区切りの全語がタイトルに含まれるものだけ残る（AND）" do
    assert_equal 1, search_with("ゴルフ")[0].size
    assert_equal 1, search_with("船橋　ゴルフ")[0].size
    assert_equal [], search_with("ゴルフ 柏")[0]
  end

  test "全角と半角、大文字小文字は同一視される" do
    assert_equal 1, search_html(card_html(title: "５０代の食事会 ABC"), "50代 abc").size
  end

  test "1 エリアの取得に失敗しても他エリアの結果は返る" do
    service = service_class.new
    stub_http_get(service, [ RuntimeError.new("HTTP 500（www.ya-7.com）"), research_fixture("ash_circle") ])

    assert_equal 2, service.search("", %w[東京 千葉]).size
  end

  test "全エリアが失敗したら最後の例外を再 raise する" do
    service = service_class.new
    stub_http_get(service, [ RuntimeError.new("HTTP 500"), RuntimeError.new("ブロックされました") ])

    error = assert_raises(RuntimeError) { service.search("", %w[東京 千葉]) }
    assert_equal "ブロックされました", error.message
  end

  test "キーワードが空なら全件残る" do
    assert_equal 2, search_with("")[0].size
  end

  test "千葉を指定すると /chiba/ を 1 回だけ取りに行く" do
    _, requested_urls = search_with("", %w[千葉])

    assert_equal [ "https://www.ya-7.com/chiba/" ], requested_urls
  end

  test "複数エリアはエリアごとに 1 回ずつ取りに行き、URL の重複は除かれる" do
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("ash_circle"), research_fixture("ash_circle") ])
    event_results = service.search("", %w[千葉 東京])

    assert_equal [ "https://www.ya-7.com/chiba/", "https://www.ya-7.com/tokyo/" ], requested_urls
    assert_equal 2, event_results.size
  end

  test "沖縄は /area_okinawa.php を取りに行く" do
    _, requested_urls = search_with("", %w[沖縄])

    assert_equal [ "https://www.ya-7.com/area_okinawa.php" ], requested_urls
  end

  test "地域が未指定ならトップページを 1 回だけ取りに行く" do
    _, requested_urls = search_with("")

    assert_equal [ "https://www.ya-7.com/" ], requested_urls
  end

  test "地域がオンラインのみならトップページを取り、オンライン表記の無いカードは落ちる" do
    event_results, requested_urls = search_with("", %w[online])

    assert_equal [ "https://www.ya-7.com/" ], requested_urls
    assert_equal [], event_results
  end

  test "地域フィルタ: トップページ経由でも千葉以外のカードは落ちる" do
    html = card_html + research_fixture("ash_circle")
    service = service_class.new
    stub_http_get(service, [ html ])

    assert_equal [ "千葉" ], service.search("", %w[千葉]).map { |event_result| event_result[:address] }.uniq
  end

  test "イベント検索（ResearchController::SERVICES）に ash_circle として登録されている" do
    assert_equal service_class, Api::ResearchController::SERVICES["ash_circle"]
  end
end
