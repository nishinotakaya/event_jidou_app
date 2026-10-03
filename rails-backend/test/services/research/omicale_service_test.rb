require "test_helper"

# オミカレ（party-calendar.net）。JSON-LD Event のパースと、地域の後段フィルタ・ページ打ち切りを検証する（HTTP は打たない）
class OmicaleServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  def service_class
    Research::OmicaleService
  end

  # 1 ページ目にフィクスチャ、2 ページ目以降は空。要求された URL も返す。
  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("omicale") ])
    [ service.search(keyword, locations), requested_urls ]
  end

  test "SITE_KEY は omicale、SITE_LABEL はオミカレ" do
    assert_equal "omicale", service_class::SITE_KEY
    assert_equal "オミカレ", service_class::SITE_LABEL
  end

  test "JSON-LD の Event 3 件を取り出し、結果の形が揃っている" do
    event_results, = search_with("婚活")

    assert_equal 3, event_results.size
    event_results.each do |event_result|
      assert_equal service_class::SITE_KEY, event_result[:site]
      assert_equal service_class::SITE_LABEL, event_result[:siteLabel]
    end
  end

  test "先頭の Event を title・url・startsAt・venue・address・capacity・participants・image に割り当てる" do
    event_results, = search_with("婚活")
    first_event = event_results.first

    assert_equal "男性急募！【同年代コン】年が近いから最初から話しやすい♡全員と1対1トーク×完全貸切会場", first_event[:title]
    assert_equal "https://party-calendar.net/detail/4505890", first_event[:url]
    assert_equal Time.iso8601("2026-10-03T14:00:00+09:00"), Time.iso8601(first_event[:startsAt])
    assert_equal "2026年10月3日 14:00", first_event[:datetimeText]
    assert_equal "池袋", first_event[:venue]
    assert_equal "東京都", first_event[:address]
    assert_equal "https://cdn.party-calendar.net/images/party/4505890_main.jpg", first_event[:imageUrl]
    assert_equal 18, first_event[:capacity]
    assert_equal 16, first_event[:participants]
  end

  test "maximum も remaining も無ければ capacity・participants は nil" do
    event_results, = search_with("婚活")
    sagamihara_event = event_results.find { |event_result| event_result[:venue] == "相模原市" }

    assert_nil sagamihara_event[:capacity]
    assert_nil sagamihara_event[:participants]
  end

  test "maximum だけあって remaining が無ければ capacity は入り participants は nil" do
    event_results, = search_with("婚活")
    umeda_event = event_results.find { |event_result| event_result[:venue] == "梅田" }

    assert_equal 24, umeda_event[:capacity]
    assert_nil umeda_event[:participants]
  end

  test "keyword は CGI エスケープされ、page 番号が付く。2 ページ目が空なら 3 ページ目は取りに行かない" do
    _, requested_urls = search_with("婚活 パーティー&街コン")

    assert_equal [
      "https://party-calendar.net/search?keyword=#{CGI.escape('婚活 パーティー&街コン')}&page=1",
      "https://party-calendar.net/search?keyword=#{CGI.escape('婚活 パーティー&街コン')}&page=2"
    ], requested_urls
  end

  test "地域に東京を選ぶと東京の Event だけ残る" do
    event_results, = search_with("婚活", %w[東京])

    assert_equal [ "池袋" ], event_results.map { |event_result| event_result[:venue] }
    assert(event_results.all? { |event_result| event_result[:address] == "東京都" })
  end

  test "地域に大阪を選ぶと東京・神奈川は落ちる" do
    event_results, = search_with("婚活", %w[大阪])

    assert_equal [ "梅田" ], event_results.map { |event_result| event_result[:venue] }
  end

  test "地域にオンラインを選ぶと 0 件" do
    event_results, = search_with("婚活", %w[online])

    assert_equal [], event_results
  end

  test "1 ページ目が空なら 1 回だけ要求して空配列を返す" do
    service = service_class.new
    requested_urls = stub_http_get(service, [ "" ])

    assert_equal [], service.search("婚活", [])
    assert_equal 1, requested_urls.size
  end

  test "イベント検索（ResearchController::SERVICES）に omicale として登録されている" do
    assert_equal service_class, Api::ResearchController::SERVICES["omicale"]
  end
end
