require "test_helper"

# EVENT CONTACT（event-contact.com）。JSON API のパース、JST 解釈、全件取得後のキーワード AND・「少人数」判定・地域フィルタを検証する（HTTP は打たない）
class EventContactServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  def service_class
    Research::EventContactService
  end

  def fixture_body
    file_fixture("research/event_contact.json").read.force_encoding(Encoding::UTF_8)
  end

  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ fixture_body ])
    [ service.search(keyword, locations), requested_urls ]
  end

  def find_by_id(event_results, id)
    event_results.find { |event_result| event_result[:url].end_with?("/#{id}") }
  end

  test "SITE_KEY は event_contact、SITE_LABEL は EVENT CONTACT" do
    assert_equal "event_contact", service_class::SITE_KEY
    assert_equal "EVENT CONTACT", service_class::SITE_LABEL
  end

  test "キーワードが空なら 5 件すべて返り、結果の形が揃い searchableText は漏れない" do
    event_results, = search_with("")

    assert_equal 5, event_results.size
    event_results.each do |event_result|
      assert_equal service_class::SITE_KEY, event_result[:site]
      assert_equal service_class::SITE_LABEL, event_result[:siteLabel]
      assert_not event_result.key?(:searchableText)
    end
  end

  test "url は /event/detail/{id}" do
    event_results, = search_with("")

    assert_equal "https://event-contact.com/event/detail/11262", find_by_id(event_results, 11262)[:url]
  end

  test "要求 URL に index.php/api/activity/index と limit・page が入り、2 ページ目が空なら打ち切る" do
    service = service_class.new
    requested_urls = stub_http_get(service, [ fixture_body, JSON.generate(code: 1, msg: "", data: { list: [] }) ])
    service.search("")

    assert_equal [
      "https://event-contact.com/index.php/api/activity/index?limit=200&page=1",
      "https://event-contact.com/index.php/api/activity/index?limit=200&page=2"
    ], requested_urls
  end

  test "2 ページ目が同じ内容でも新規 URL が無ければ 3 ページ目は取らない" do
    service = service_class.new
    requested_urls = stub_http_get(service, [ fixture_body, fixture_body, fixture_body ])

    assert_equal 5, service.search("").size
    assert_equal 2, requested_urls.size
  end

  test "date と start は JST として読み、datetimeText は終了時刻付き" do
    first_event = find_by_id(search_with("")[0], 11262)
    starts_at = Time.iso8601(first_event[:startsAt])

    assert_equal Time.iso8601("2026-10-28T13:30:00+09:00"), starts_at
    assert_equal 9 * 3600, starts_at.utc_offset
    assert_equal "2026年10月28日 13:30〜14:30", first_event[:datetimeText]
  end

  test "date と start が欠けた会は startsAt・datetimeText が nil で残る" do
    body = JSON.parse(fixture_body)
    body["data"]["list"].each { |activity| activity.merge!("date" => nil, "start" => "") }
    service = service_class.new
    stub_http_get(service, [ JSON.generate(body) ])
    first_event = service.search("").first

    assert_nil first_event[:startsAt]
    assert_nil first_event[:datetimeText]
  end

  test "end が無ければ datetimeText に 〜 以降を付けない" do
    body = JSON.parse(fixture_body)
    body["data"]["list"].each { |activity| activity["end"] = nil }
    service = service_class.new
    stub_http_get(service, [ JSON.generate(body) ])

    assert_equal "2026年10月28日 13:30", service.search("").first[:datetimeText]
  end

  test "venue は最寄駅の説明、address は都道府県＋市区町村＋住所（改行は空白に潰す）" do
    first_event = find_by_id(search_with("")[0], 11262)

    assert_equal "ＪＲ山手線他【渋谷駅】徒歩4分 セブンイレブンの隣のビルとなります。 3階へお越しください。", first_event[:venue]
    assert_equal "東京都渋谷区 渋谷１－１１－３ 第一小山ビル３F", first_event[:address]
    assert_equal "EVENT CONTACT", first_event[:organizer]
  end

  test "countyText が null の会は住所だけが address になる" do
    event_result = find_by_id(search_with("")[0], 11288)

    assert_equal "群馬県高崎市通町90-7 ＡＲＣビル３Ｆ カリマ高崎", event_result[:address]
  end

  test "capacity は男女の定員合計、participants は定員から残席を引いた数、定員 0,0 は両方 nil" do
    event_results, = search_with("")
    full_seats = find_by_id(event_results, 11262)
    partly_booked = find_by_id(event_results, 11267)
    unknown_capacity = find_by_id(event_results, 11151)

    assert_equal [ 4, 0 ], [ full_seats[:capacity], full_seats[:participants] ]
    assert_equal [ 4, 1 ], [ partly_booked[:capacity], partly_booked[:participants] ]
    assert_nil unknown_capacity[:capacity]
    assert_nil unknown_capacity[:participants]
  end

  test "残席が定員を超える異常値なら participants は nil" do
    body = JSON.parse(fixture_body)
    body["data"]["list"].each { |activity| activity.merge!("m_surplus" => 9, "w_surplus" => 9) }
    service = service_class.new
    stub_http_get(service, [ JSON.generate(body) ])

    assert_nil find_by_id(service.search(""), 11262)[:participants]
  end

  test "画像は http を https に置き換える" do
    first_event = find_by_id(search_with("")[0], 11262)

    assert_equal "https://realing.oss-ap-northeast-1.aliyuncs.com/2026/09/19/b2b9730ff37938e7249c20e78fe6c330.png", first_event[:imageUrl]
  end

  test "画像が javascript: なら画像だけ nil で結果は残る" do
    body = JSON.parse(fixture_body)
    body["data"]["list"].each { |activity| activity["image"] = "javascript:alert(1)" }
    service = service_class.new
    stub_http_get(service, [ JSON.generate(body) ])
    event_results = service.search("")

    assert_equal 5, event_results.size
    assert_nil event_results.first[:imageUrl]
  end

  test "キーワードは空白区切りの AND で、存在しない語は 0 件" do
    assert_equal 1, search_with("渋谷 同年代")[0].size
    assert_equal [], search_with("渋谷 存在しない語")[0]
    assert_equal [], search_with("存在しない語")[0]
  end

  test "全角半角・大文字小文字を同一視する（駅名の全角英数字・形式の 1対1）" do
    assert_equal 2, search_with("ｊｒ山手線")[0].size
    assert_equal 4, search_with("１対１")[0].size
  end

  test "「少人数」はタイトルに無い 2対2 の会にもヒットし、定員 0 の会にはヒットしない" do
    event_results, = search_with("少人数")
    ids = event_results.map { |event_result| event_result[:url][%r{\d+\z}].to_i }

    assert_includes ids, 11267 # タイトルに「少人数」あり
    assert_includes ids, 11262 # タイトルに無いが男女各 2 名
    assert_not_includes ids, 11151 # 定員 0,0（不明）
  end

  test "地域に東京を選ぶと東京都の 3 件、千葉なら 1 件、大阪なら 0 件" do
    assert_equal [ 11262, 11267, 11151 ].sort, search_with("", %w[東京])[0].map { |event_result| event_result[:url][%r{\d+\z}].to_i }.sort
    assert_equal [ "https://event-contact.com/event/detail/11072" ], search_with("", %w[千葉])[0].map { |event_result| event_result[:url] }
    assert_equal [], search_with("", %w[大阪])[0]
  end

  test "id が無い・件名が空の要素は捨てられる" do
    body = JSON.parse(fixture_body)
    body["data"]["list"][0]["id"] = nil
    body["data"]["list"][1]["name"] = " "
    service = service_class.new
    stub_http_get(service, [ JSON.generate(body) ])

    assert_equal 3, service.search("").size
  end

  test "code が 1 以外・list が配列でないレスポンスは 0 件ではなく例外にする" do
    [ { code: 0, msg: "error", data: { list: [] } }, { code: 1, msg: "", data: { list: nil } }, { code: 1, msg: "" } ].each do |payload|
      service = service_class.new
      stub_http_get(service, [ JSON.generate(payload) ])

      assert_raises(RuntimeError) { service.search("") }
    end
  end

  test "イベント検索（ResearchController::SERVICES）に event_contact として登録されている" do
    assert_equal service_class, Api::ResearchController::SERVICES["event_contact"]
  end
end
