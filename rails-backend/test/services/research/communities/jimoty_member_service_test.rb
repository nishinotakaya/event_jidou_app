require "test_helper"

# ジモティー メンバー募集（/all/com）検索。既存 JimotyService と同じ DOM と、地域の後段フィルタを検証する（HTTP は打たない）
class JimotyMemberServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  KEYWORD = "経営者 交流会".freeze

  def service_class
    Research::Communities::JimotyMemberService
  end

  def search_with_pages(page_bodies, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, page_bodies)
    [ service.search(KEYWORD, locations), requested_urls ]
  end

  test "SITE_KEY は jimoty_member" do
    assert_equal "jimoty_member", service_class::SITE_KEY
  end

  test "カードを name・url・area・imageUrl に変換する" do
    community_results, = search_with_pages([ research_fixture("jimoty_member") ])

    assert_equal 3, community_results.size
    first_result = community_results.first
    assert_community_result_shape(first_result, service_class)
    assert_equal "仙台のカラオケサークル参加者募集中！", first_result[:name]
    assert_equal "https://jmty.jp/miyagi/com-fri/article-19zddu", first_result[:url]
    assert_equal "宮城", first_result[:area]
    assert first_result[:imageUrl].start_with?("https://cdn.jmty.jp/assets/article/no_img")
  end

  test "エリアの違うカードがそれぞれ取れる" do
    community_results, = search_with_pages([ research_fixture("jimoty_member") ])

    assert_equal %w[宮城 東京 大阪], community_results.map { |result| result[:area] }
    assert_equal "https://cdn.jmty.jp/articles/images/6ac073f0727da669ed62c258/thumb_m_file.jpg", community_results[1][:imageUrl]
  end

  test "地域を選ぶとその地域のカードだけ残る" do
    community_results, = search_with_pages([ research_fixture("jimoty_member") ], %w[東京])

    assert_equal [ "日帰り登山仲間募集⛰️✨" ], community_results.map { |result| result[:name] }
  end

  test "複数地域はいずれかに一致するカードが残る" do
    community_results, = search_with_pages([ research_fixture("jimoty_member") ], %w[東京 大阪])

    assert_equal %w[東京 大阪], community_results.map { |result| result[:area] }
  end

  test "該当地域が無ければ 0 件" do
    community_results, = search_with_pages([ research_fixture("jimoty_member") ], %w[神奈川])

    assert_equal [], community_results
  end

  test "要求 URL は /all/com に keyword と page を付ける" do
    _, requested_urls = search_with_pages([ research_fixture("jimoty_member") ])

    assert_equal "https://jmty.jp/all/com?keyword=#{CGI.escape(KEYWORD)}&page=1", requested_urls.first
    assert_equal "https://jmty.jp/all/com?keyword=#{CGI.escape(KEYWORD)}&page=2", requested_urls[1]
  end

  test "2 ページ目が 404 でも 1 ページ目の結果を返す" do
    community_results, requested_urls = search_with_pages([ research_fixture("jimoty_member"), RuntimeError.new("HTTP 404（jmty.jp）") ])

    assert_equal 2, requested_urls.size
    assert_equal 3, community_results.size
  end

  test "404 以外のエラーは握りつぶさず投げる" do
    assert_raises(RuntimeError) do
      search_with_pages([ RuntimeError.new("HTTP 500（jmty.jp）") ])
    end
  end

  test "新規 URL が無いページが来たら打ち切る" do
    page_one = research_fixture("jimoty_member")
    community_results, requested_urls = search_with_pages([ page_one, page_one, page_one ])

    assert_equal 2, requested_urls.size
    assert_equal 3, community_results.size
  end
end
