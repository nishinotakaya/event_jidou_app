require "test_helper"

# フィオーレパーティー（www.fiore-party.com）。都道府県ページの JSON-LD パースと、name + description のキーワード AND 絞り込み・URL 選択・範囲外ページの打ち切りを検証する（HTTP は打たない）
class FioreServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  def service_class
    Research::FioreService
  end

  # フィクスチャを全ページの応答にする（範囲外ページが 1 ページ目と同じ内容を返す実サイトの挙動の再現）。
  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, Array.new(10) { research_fixture("fiore") })
    [ service.search(keyword, locations), requested_urls ]
  end

  def event_json_ld(overrides)
    event = {
      "@type" => "Event", "name" => "テスト", "startDate" => "2026/10/12 11:40:00", "description" => "説明文",
      "url" => "https://www.fiore-party.com/party_detail/a", "image" => "https://example.com/a.png",
      "location" => { "@type" => "Place", "name" => "会場", "address" => { "addressRegion" => "東京都" } }
    }.merge(overrides)
    %(<script type="application/ld+json">#{[ event ].to_json}</script>)
  end

  def search_html(html, keyword = "")
    service = service_class.new
    stub_http_get(service, [ html ])
    service.search(keyword)
  end

  test "SITE_KEY は fiore、SITE_LABEL はフィオーレパーティー" do
    assert_equal "fiore", service_class::SITE_KEY
    assert_equal "フィオーレパーティー", service_class::SITE_LABEL
  end

  test "JSON-LD の Event 配列 3 件を取り出し、結果の形が揃っている（内部用の searchableText は返さない）" do
    event_results, = search_with("")

    assert_equal 3, event_results.size
    event_results.each do |event_result|
      assert_equal service_class::SITE_KEY, event_result[:site]
      assert_equal service_class::SITE_LABEL, event_result[:siteLabel]
      assert_not event_result.key?(:searchableText)
    end
  end

  test "先頭の Event を title・url・venue・address・organizer・image に割り当てる" do
    first_event = search_with("")[0].first

    assert_equal "価値観の合うお相手を探そう！【性格タイプ相性診断付き♪20・30代中心編】", first_event[:title]
    assert_equal "https://www.fiore-party.com/party_detail/YZcu6OpvKd", first_event[:url]
    assert_equal "岡山駅前個室会場", first_event[:venue]
    assert_equal "岡山県", first_event[:address]
    assert_equal "フィオーレパーティー", first_event[:organizer]
    assert_equal "https://www.fiore-party.com/App_Contents/upload_img/smmbti20tyushin.jpg", first_event[:imageUrl]
  end

  test "タイムゾーン無しのスラッシュ区切り startDate は JST として読む" do
    first_event = search_with("")[0].first
    starts_at = Time.iso8601(first_event[:startsAt])

    assert_equal Time.iso8601("2026-10-10T16:30:00+09:00"), starts_at
    assert_equal 9 * 3600, starts_at.utc_offset
    assert_equal "2026年10月10日 16:30", first_event[:datetimeText]
  end

  test "url が javascript: の Event は捨てられる" do
    assert_equal [], search_html(event_json_ld("url" => "javascript:alert(1)"))
  end

  test "image が配列なら先頭、http(s) でなければ画像だけ nil" do
    assert_equal "https://example.com/1.png", search_html(event_json_ld("image" => [ "https://example.com/1.png", "https://example.com/2.png" ])).first[:imageUrl]
    assert_nil search_html(event_json_ld("image" => "javascript:alert(1)")).first[:imageUrl]
  end

  test "address が文字列ならそのまま使う" do
    event_results = search_html(event_json_ld("location" => { "name" => "会場", "address" => "東京都千代田区" }))

    assert_equal "東京都千代田区", event_results.first[:address]
  end

  test "address が Hash で addressRegion が無ければ addressLocality を使う" do
    event_results = search_html(event_json_ld("location" => { "name" => "会場", "address" => { "addressLocality" => "柏市" } }))

    assert_equal "柏市", event_results.first[:address]
  end

  test "location.name が文字列でなければ venue は nil" do
    event_results = search_html(event_json_ld("location" => { "name" => { "x" => 1 }, "address" => "東京都" }))

    assert_equal 1, event_results.size
    assert_nil event_results.first[:venue]
  end

  test "タイトルが空の Event は捨てられる" do
    assert_equal [], search_html(event_json_ld("name" => " "))
  end

  test "全角と半角は同一視される" do
    assert_equal 1, search_html(event_json_ld("name" => "５０代限定"), "50代").size
  end

  test "1 つの都道府県の取得に失敗しても他の結果は返る" do
    service = service_class.new
    stub_http_get(service, [ RuntimeError.new("HTTP 500"), research_fixture("fiore") ])

    assert_equal %w[東京都 千葉県], service.search("", %w[東京 千葉]).map { |event_result| event_result[:address] }
  end

  test "全部の都道府県が失敗したら最後の例外を再 raise する" do
    service = service_class.new
    stub_http_get(service, [ RuntimeError.new("HTTP 500"), RuntimeError.new("ブロックされました") ])

    error = assert_raises(RuntimeError) { service.search("", %w[東京 千葉]) }
    assert_equal "ブロックされました", error.message
  end

  test "キーワードは name + description の全語 AND（部分一致）" do
    assert_equal 1, search_with("岡山駅前")[0].size
    assert_equal 1, search_with("個室 アラサー")[0].size
    assert_equal [], search_with("個室 存在しない語")[0]
  end

  test "description だけに含まれる語でも絞り込める" do
    event_results = search_html(event_json_ld("description" => "千葉県/柏駅/会場"), "柏駅")

    assert_equal 1, event_results.size
    assert_equal [], search_html(event_json_ld("description" => "千葉県/柏駅/会場"), "渋谷")
  end

  test "千葉を指定すると pref_chiba を取りに行き、範囲外ページ（1 ページ目と同内容）で打ち切る" do
    event_results, requested_urls = search_with("", %w[千葉])

    assert_equal [
      "https://www.fiore-party.com/pref/pref_chiba?pageIndex=1",
      "https://www.fiore-party.com/pref/pref_chiba?pageIndex=2"
    ], requested_urls
    assert_equal [ "千葉県" ], event_results.map { |event_result| event_result[:address] }
  end

  test "地域が未指定なら pref_all を取りに行く" do
    _, requested_urls = search_with("")

    assert_equal "https://www.fiore-party.com/pref/pref_all?pageIndex=1", requested_urls.first
    assert(requested_urls.all? { |url| url.include?("/pref/pref_all?") })
  end

  test "複数地域は slug ごとに取りに行き、URL の重複は除かれる" do
    event_results, requested_urls = search_with("", %w[東京 千葉])

    assert_equal %w[pref_tokyo pref_chiba], requested_urls.map { |url| url[%r{pref/(pref_\w+)\?}, 1] }.uniq
    assert_equal 2, event_results.size
  end

  test "地域フィルタ: 東京を選ぶと東京都の Event だけ残る" do
    event_results, = search_with("", %w[東京])

    assert_equal [ "東京都" ], event_results.map { |event_result| event_result[:address] }
  end

  test "1 ページ目が空なら 1 回だけ要求して空配列を返す" do
    service = service_class.new
    requested_urls = stub_http_get(service, [ "" ])

    assert_equal [], service.search("", [])
    assert_equal 1, requested_urls.size
  end

  test "イベント検索（ResearchController::SERVICES）に fiore として登録されている" do
    assert_equal service_class, Api::ResearchController::SERVICES["fiore"]
  end
end
