require "test_helper"

# PARTY☆PARTY（www.partyparty.jp）。JSON-LD Event のパースと、地域の後段フィルタ・ページ打ち切りを検証する（HTTP は打たない）
class PartypartyServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  KEYWORD_PARAMETER = "member_party_detail_search%5Bfreeword%5D".freeze

  def service_class
    Research::PartypartyService
  end

  # 1 ページ目にフィクスチャ、2 ページ目以降は空。要求された URL も返す。
  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("partyparty") ])
    [ service.search(keyword, locations), requested_urls ]
  end

  def event_json_ld(overrides)
    event = {
      "@context" => "https://schema.org/", "@type" => "Event", "name" => "テスト", "startDate" => "2026-10-12T11:40+09:00",
      "url" => "https://www.partyparty.jp/party-detail/pid1", "image" => "https://example.com/a.png",
      "location" => { "@type" => "Place", "name" => "会場", "address" => { "addressRegion" => "東京都" } }
    }.merge(overrides)
    %(<script type="application/ld+json">#{event.to_json}</script>)
  end

  def search_html(html)
    service = service_class.new
    stub_http_get(service, [ html ])
    service.search("スポーツ")
  end

  test "url が javascript: の Event は捨てられる" do
    event_results = search_html(event_json_ld("url" => "javascript:alert(1)"))

    assert_equal [], event_results
  end

  test "image が配列なら先頭が採用される" do
    event_results = search_html(event_json_ld("image" => [ "https://example.com/first.png", "https://example.com/second.png" ]))

    assert_equal "https://example.com/first.png", event_results.first[:imageUrl]
  end

  test "image が http(s) でなければ画像だけ nil で結果は残る" do
    event_results = search_html(event_json_ld("image" => "javascript:alert(1)"))

    assert_equal 1, event_results.size
    assert_nil event_results.first[:imageUrl]
  end

  test "address や organizer が文字列でも例外にならない" do
    event_results = search_html(event_json_ld(
      "location" => { "@type" => "Place", "name" => "会場", "address" => "東京都千代田区" }, "organizer" => "IBJ Matching"
    ))

    assert_equal 1, event_results.size
    assert_nil event_results.first[:address]
    assert_nil event_results.first[:organizer]
  end

  test "SITE_KEY は partyparty、SITE_LABEL は PARTY☆PARTY" do
    assert_equal "partyparty", service_class::SITE_KEY
    assert_equal "PARTY☆PARTY", service_class::SITE_LABEL
  end

  test "JSON-LD の Event 3 件を取り出し、結果の形が揃っている" do
    event_results, = search_with("スポーツ")

    assert_equal 3, event_results.size
    event_results.each do |event_result|
      assert_equal service_class::SITE_KEY, event_result[:site]
      assert_equal service_class::SITE_LABEL, event_result[:siteLabel]
    end
  end

  test "先頭の Event を title・url・startsAt・venue・address・organizer・image に割り当てる" do
    event_results, = search_with("スポーツ")
    first_event = event_results.first

    assert_equal "《高身長175cm以上×年収600万以上の男性》 笑顔が魅力的な明るい女性", first_event[:title]
    assert_equal "https://www.partyparty.jp/party-detail/pid1800989", first_event[:url]
    assert_equal "有楽町ラウンジ", first_event[:venue]
    assert_equal "東京都", first_event[:address]
    assert_equal "IBJ Matching", first_event[:organizer]
    assert_equal "https://www-partyparty-jp-data.s3-ap-northeast-1.amazonaws.com/upload/party_image/image/5944.png", first_event[:imageUrl]
  end

  test "秒の無い startDate（2026-10-12T11:40+09:00）を読める" do
    event_results, = search_with("スポーツ")
    first_event = event_results.first

    assert_equal Time.iso8601("2026-10-12T11:40:00+09:00"), Time.iso8601(first_event[:startsAt])
    assert_equal "2026年10月12日 11:40", first_event[:datetimeText]
  end

  test "organizer が無ければ nil（performer のスタッフ表記は使わない）" do
    event_results, = search_with("スポーツ")
    osaka_event = event_results.find { |event_result| event_result[:address] == "大阪府" }

    assert_nil osaka_event[:organizer]
  end

  test "VirtualLocation のオンライン開催は venue が オンライン・address が nil" do
    event_results, = search_with("スポーツ")
    online_event = event_results.find { |event_result| event_result[:url].end_with?("pid1813803") }

    assert_equal "オンライン", online_event[:venue]
    assert_nil online_event[:address]
    assert_equal "《オンラインマッチング♪》 身だしなみに気を使っている方", online_event[:title]
  end

  test "keyword は member_party_detail_search[freeword] に CGI エスケープで入り、page 番号が付く。2 ページ目が空なら 3 ページ目は取りに行かない" do
    _, requested_urls = search_with("スポーツ 観戦&街コン")

    escaped_keyword = CGI.escape("スポーツ 観戦&街コン")
    assert_equal [
      "https://www.partyparty.jp/party_detail_search/search?#{KEYWORD_PARAMETER}=#{escaped_keyword}&page=1",
      "https://www.partyparty.jp/party_detail_search/search?#{KEYWORD_PARAMETER}=#{escaped_keyword}&page=2"
    ], requested_urls
  end

  test "地域に東京を選ぶと東京の Event だけ残る" do
    event_results, = search_with("スポーツ", %w[東京])

    assert_equal [ "有楽町ラウンジ" ], event_results.map { |event_result| event_result[:venue] }
  end

  test "地域に大阪を選ぶと東京とオンラインは落ちる" do
    event_results, = search_with("スポーツ", %w[大阪])

    assert_equal [ "梅田ラウンジ" ], event_results.map { |event_result| event_result[:venue] }
  end

  test "地域にオンラインを選ぶとオンライン開催だけ残る" do
    event_results, = search_with("スポーツ", %w[online])

    assert_equal [ "オンライン" ], event_results.map { |event_result| event_result[:venue] }
  end

  test "1 ページ目が空なら 1 回だけ要求して空配列を返す" do
    service = service_class.new
    requested_urls = stub_http_get(service, [ "" ])

    assert_equal [], service.search("スポーツ", [])
    assert_equal 1, requested_urls.size
  end

  test "イベント検索（ResearchController::SERVICES）に partyparty として登録されている" do
    assert_equal service_class, Api::ResearchController::SERVICES["partyparty"]
  end
end
