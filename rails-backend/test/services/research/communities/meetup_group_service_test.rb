require "test_helper"

# Meetup グループ検索。#__NEXT_DATA__ の Apollo キャッシュ（Group / PhotoInfo）のパースを検証する（HTTP は打たない）
class MeetupGroupServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  KEYWORD = "AI 交流会".freeze

  def service_class
    Research::Communities::MeetupGroupService
  end

  def search_with_pages(page_bodies, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, page_bodies)
    [ service.search(KEYWORD, locations), requested_urls ]
  end

  test "SITE_KEY は meetup_group" do
    assert_equal "meetup_group", service_class::SITE_KEY
  end

  test "Group を name・url・description・area・memberCount・imageUrl に変換する" do
    community_results, = search_with_pages([ research_fixture("meetup_group") ])

    assert_equal 3, community_results.size
    first_result = community_results.first
    assert_community_result_shape(first_result, service_class)
    assert_equal "eLifes AI技術者の集い ＆ CoderBar勉強会", first_result[:name]
    assert_equal "https://www.meetup.com/elifes-ai技術者の集い-coderbar勉強会", first_result[:url]
    assert first_result[:description].start_with?("実践的なAI技術の学びと交流を目的としたコミュニティです。")
    assert_equal "Tokyo", first_result[:area]
    assert_equal 4, first_result[:memberCount]
    assert_kind_of Integer, first_result[:memberCount]
  end

  test "groupPhoto の参照先 PhotoInfo から imageUrl を組み立てる" do
    community_results, = search_with_pages([ research_fixture("meetup_group") ])

    assert community_results[0][:imageUrl].start_with?("https://secure-content.meetupstatic.com/images/classic-events/535942165")
    assert community_results[1][:imageUrl].start_with?("https://secure-content.meetupstatic.com/images/classic-events/535202251")
  end

  test "groupPhoto が無いグループは imageUrl が nil" do
    community_results, = search_with_pages([ research_fixture("meetup_group") ])

    no_photo_result = community_results.find { |result| result[:name] == "Nekojarashi Tokyo" }
    assert_not_nil no_photo_result
    assert_nil no_photo_result[:imageUrl]
    assert_equal 1, no_photo_result[:memberCount]
  end

  test "メンバー数は整数で、グループごとに違う" do
    community_results, = search_with_pages([ research_fixture("meetup_group") ])

    assert_equal [ 4, 365, 1 ], community_results.map { |result| result[:memberCount] }
  end

  test "地域未選択は東京の slug で GROUPS を検索する（1 リクエスト）" do
    _, requested_urls = search_with_pages([ research_fixture("meetup_group") ])

    assert_equal 1, requested_urls.size
    assert_includes requested_urls.first, "source=GROUPS"
    assert_includes requested_urls.first, "keywords=#{CGI.escape(KEYWORD)}"
    assert_includes requested_urls.first, "location=#{CGI.escape(Research::MeetupService::LOCATION_SLUGS['東京'])}"
  end

  test "地域を選ぶとその地域の slug で検索する" do
    _, requested_urls = search_with_pages([ research_fixture("meetup_group") ], %w[大阪])

    assert_includes requested_urls.first, "location=#{CGI.escape(Research::MeetupService::LOCATION_SLUGS['大阪'])}"
    assert_not_includes requested_urls.first, "jp--Tokyo"
  end

  test "複数地域は地域ごとに 1 リクエストで、同じ URL のグループは重複除去される" do
    community_results, requested_urls = search_with_pages([ research_fixture("meetup_group"), research_fixture("meetup_group") ], %w[東京 大阪])

    assert_equal 2, requested_urls.size
    assert_equal 3, community_results.size
  end

  test "グループが無いページなら 0 件" do
    empty_page = '<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"__APOLLO_STATE__":{}}}}</script>'
    community_results, = search_with_pages([ empty_page ])

    assert_equal [], community_results
  end
end
