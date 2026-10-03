require "test_helper"

# Meetup グループは地域ごとに並列取得する。一部の地域が落ちても残りを返し、全滅したときだけ例外にする
# （例外にしないと ParallelSiteSearch のサイト単位エラー表示に出ない）。HTTP は打たない。
class MeetupGroupPartialFailureTest < ActiveSupport::TestCase
  include ResearchHttpStub

  KEYWORD = "AI 交流会".freeze
  LOCATIONS = %w[東京 大阪].freeze

  # リクエスト順に依存しないよう、URL の location= で地域ごとの応答（本文または例外）を選ぶ
  def stub_http_get_by_location(service, response_by_location_slug)
    service.define_singleton_method(:http_get) do |url, _headers = {}|
      location_slug = Rack::Utils.parse_query(URI(url).query)["location"]
      response = response_by_location_slug.fetch(location_slug) { raise "想定外の location: #{location_slug.inspect}" }
      raise response if response.is_a?(Exception)

      response
    end
  end

  def location_slug_of(location_name)
    Research::MeetupService::LOCATION_SLUGS.fetch(location_name)
  end

  def build_service(response_by_location_name)
    service = Research::Communities::MeetupGroupService.new
    response_by_slug = response_by_location_name.transform_keys { |location_name| location_slug_of(location_name) }
    stub_http_get_by_location(service, response_by_slug)
    service
  end

  test "大阪だけ失敗しても東京の結果が返る" do
    service = build_service("東京" => research_fixture("meetup_group"), "大阪" => RuntimeError.new("HTTP 500"))

    community_results = service.search(KEYWORD, LOCATIONS)

    assert_equal 3, community_results.size
  end

  test "東京だけ失敗しても大阪の結果が返る" do
    service = build_service("東京" => RuntimeError.new("HTTP 500"), "大阪" => research_fixture("meetup_group"))

    community_results = service.search(KEYWORD, LOCATIONS)

    assert_equal 3, community_results.size
  end

  test "全地域が失敗したら例外を投げる" do
    service = build_service("東京" => RuntimeError.new("HTTP 500"), "大阪" => RuntimeError.new("HTTP 503"))

    assert_raises(RuntimeError) { service.search(KEYWORD, LOCATIONS) }
  end

  test "全地域が成功したら両方の結果を url で重複除去して返す" do
    service = build_service("東京" => research_fixture("meetup_group"), "大阪" => research_fixture("meetup_group"))

    assert_equal 3, service.search(KEYWORD, LOCATIONS).size
  end
end
