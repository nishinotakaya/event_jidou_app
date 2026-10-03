require "test_helper"

# CAMPFIREコミュニティ検索。HTML（.fc-card）のパースと、会費を取らない・地域を無視する仕様を検証する（HTTP は打たない）
class CampfireServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  KEYWORD = "経営者 交流会".freeze
  FIRST_IMAGE_URL = "https://static.camp-fire.jp/uploads/project_version/image/1635635/medium_c8041432-72a4-404c-82fe-16c5ede34d24.jpeg?auto=format&ref=ix_tag".freeze

  def service_class
    Research::Communities::CampfireService
  end

  def search_with_pages(page_bodies, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, page_bodies)
    [ service.search(KEYWORD, locations), requested_urls ]
  end

  test "SITE_KEY は campfire" do
    assert_equal "campfire", service_class::SITE_KEY
  end

  test "カードを name・url・imageUrl・organizer に変換し、fee は nil・area はオンライン" do
    community_results, = search_with_pages([ research_fixture("campfire") ])

    assert_equal 3, community_results.size
    first_result = community_results.first
    assert_community_result_shape(first_result, service_class)
    assert_equal "「何かお手伝い　できますか？」　経営者のコミュニティー「志labo」", first_result[:name]
    assert_equal "https://community.camp-fire.jp/projects/view/835017", first_result[:url]
    assert_equal FIRST_IMAGE_URL, first_result[:imageUrl]
    assert_equal "kirishima style", first_result[:organizer]
    assert_nil first_result[:fee]
    assert_equal "オンライン", first_result[:area]
  end

  test "2 件目以降の url と主宰者" do
    community_results, = search_with_pages([ research_fixture("campfire") ])

    assert_equal %w[835017 868583 856694], community_results.map { |result| result[:url][%r{/projects/view/(\d+)}, 1] }
    assert_equal [ "kirishima style", "BIZ-LAB. 篠原啓祐", "GlobalClub" ], community_results.map { |result| result[:organizer] }
  end

  test "主宰者のプロフィール画像ではなくプロジェクトのサムネイルを imageUrl にする" do
    community_results, = search_with_pages([ research_fixture("campfire") ])

    assert(community_results.none? { |result| result[:imageUrl].include?("profile_image") })
  end

  test "地域を指定しても結果は変わらない（地域指定は無視）" do
    without_location, = search_with_pages([ research_fixture("campfire") ])
    with_location, = search_with_pages([ research_fixture("campfire") ], %w[大阪])

    assert_equal 3, with_location.size
    assert_equal without_location, with_location
  end

  test "最初の要求 URL は community.camp-fire.jp の検索で、キーワードが CGI エスケープされる" do
    _, requested_urls = search_with_pages([ research_fixture("campfire") ])

    assert requested_urls.first.start_with?("https://community.camp-fire.jp/projects/search?")
    assert_includes requested_urls.first, "word=#{CGI.escape(KEYWORD)}"
  end

  test "2 ページ目は page=2 で取りに行く" do
    page_one = research_fixture("campfire")
    page_two = page_one.gsub("/projects/view/", "/projects/view/9")
    community_results, requested_urls = search_with_pages([ page_one, page_two ])

    assert_includes requested_urls[1], "page=2"
    assert_equal 6, community_results.size
  end

  test "新規 URL が無いページが来たら打ち切り、重複は除かれる" do
    page_one = research_fixture("campfire")
    community_results, requested_urls = search_with_pages([ page_one, page_one, page_one ])

    assert_equal 2, requested_urls.size
    assert_equal 3, community_results.size
  end

  test "空ページなら 0 件" do
    community_results, = search_with_pages([ "" ])

    assert_equal [], community_results
  end
end
