require "test_helper"

# DMMオンラインサロン検索。HTML（.c-salonCard）のパースと、地域指定を無視する仕様を検証する（HTTP は打たない）
class DmmSalonServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  KEYWORD = "経営者 交流会".freeze

  def service_class
    Research::Communities::DmmSalonService
  end

  def search_with_pages(page_bodies, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, page_bodies)
    [ service.search(KEYWORD, locations), requested_urls ]
  end

  test "SITE_KEY は dmm_salon" do
    assert_equal "dmm_salon", service_class::SITE_KEY
  end

  test "サロンカードを name・url・description・fee・area に変換する" do
    community_results, = search_with_pages([ research_fixture("dmm_salon") ])

    assert_equal 3, community_results.size
    first_result = community_results.first
    assert_community_result_shape(first_result, service_class)
    assert_equal "旅の研究所", first_result[:name]
    assert_equal "https://lounge.dmm.com/detail/11186/", first_result[:url]
    assert first_result[:description].start_with?("旅をお得に、もっと楽しく、もっと深く。")
    assert_equal "2,980円/1ヶ月ごと", first_result[:fee]
    assert_equal "オンライン", first_result[:area]
    assert_nil first_result[:memberCount]
    assert_nil first_result[:organizer]
  end

  test "2 件目以降も name と月額が取れ、url は絶対 URL になる" do
    community_results, = search_with_pages([ research_fixture("dmm_salon") ])

    assert_equal %w[旅の研究所 eBaysellerlab Lilyの芽吹きの森], community_results.map { |result| result[:name] }
    assert_equal [ "2,980円/1ヶ月ごと", "3,300円/1ヶ月ごと", "990円/1ヶ月ごと" ], community_results.map { |result| result[:fee] }
    assert(community_results.all? { |result| result[:url].start_with?("https://lounge.dmm.com/detail/") })
  end

  test "地域を指定しても結果は変わらない（地域指定は無視）" do
    without_location, = search_with_pages([ research_fixture("dmm_salon") ])
    with_location, = search_with_pages([ research_fixture("dmm_salon") ], %w[東京])

    assert_equal 3, with_location.size
    assert_equal without_location, with_location
  end

  test "最初の要求 URL は lounge.dmm.com の検索で、キーワードが CGI エスケープされる" do
    _, requested_urls = search_with_pages([ research_fixture("dmm_salon") ])

    assert requested_urls.first.start_with?("https://lounge.dmm.com/search/")
    assert_includes requested_urls.first, "keyword=#{CGI.escape(KEYWORD)}"
  end

  test "2 ページ目は新規 URL があれば取りに行き、ページ番号が URL に入る" do
    page_one = research_fixture("dmm_salon")
    page_two = page_one.gsub("/detail/", "/detail/2")
    community_results, requested_urls = search_with_pages([ page_one, page_two ])

    assert_operator requested_urls.size, :>=, 2
    assert_match %r{page[=/]2\b}, requested_urls[1]
    assert_equal 6, community_results.size
  end

  test "新規 URL が無いページが来たら打ち切り、重複は除かれる" do
    page_one = research_fixture("dmm_salon")
    community_results, requested_urls = search_with_pages([ page_one, page_one, page_one ])

    assert_equal 2, requested_urls.size
    assert_equal 3, community_results.size
  end

  test "ページ数の上限は MAX_SEARCH_PAGES" do
    page_one = research_fixture("dmm_salon")
    distinct_pages = (1..5).map { |page_number| page_one.gsub("/detail/", "/detail/#{page_number}") }
    community_results, requested_urls = search_with_pages(distinct_pages)

    assert_equal Research::BaseService::MAX_SEARCH_PAGES, requested_urls.size
    assert_equal 9, community_results.size
  end

  test "空ページなら 0 件" do
    community_results, = search_with_pages([ "" ])

    assert_equal [], community_results
  end
end
