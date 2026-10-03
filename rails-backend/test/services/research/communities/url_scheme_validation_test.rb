require "test_helper"

# 相手サイトの href / src をそのまま返すと javascript: などが画面のリンクに流れるため、
# build_community_result が http/https 以外を弾くことを、既存サービスの公開挙動（search）で検証する（HTTP は打たない）
class CommunityUrlSchemeValidationTest < ActiveSupport::TestCase
  include ResearchHttpStub

  KEYWORD = "経営者 交流会".freeze
  FIRST_JIMOTY_TITLE = "仙台のカラオケサークル参加者募集中！".freeze
  FIRST_JIMOTY_TITLE_LINK = %(<a href="https://jmty.jp/miyagi/com-fri/article-19zddu">#{FIRST_JIMOTY_TITLE}</a>).freeze

  def search_jimoty_member(html)
    service = Research::Communities::JimotyMemberService.new
    stub_http_get(service, [ html ])
    service.search(KEYWORD, [])
  end

  def search_campfire(html)
    service = Research::Communities::CampfireService.new
    stub_http_get(service, [ html ])
    service.search(KEYWORD, [])
  end

  def jimoty_html_with_first_title_href(href)
    original_html = research_fixture("jimoty_member")
    assert_includes original_html, FIRST_JIMOTY_TITLE_LINK, "フィクスチャの前提が変わった"
    original_html.sub(FIRST_JIMOTY_TITLE_LINK, %(<a href="#{href}">#{FIRST_JIMOTY_TITLE}</a>))
  end

  def campfire_html_with_first_image_src(image_src)
    original_html = research_fixture("campfire")
    original_image_src = original_html[/data-src="([^"]*1635635[^"]*)"/, 1]
    assert original_image_src, "フィクスチャの前提が変わった"
    original_html.sub(%(data-src="#{original_image_src}"), %(data-src="#{image_src}"))
  end

  test "url が javascript: のカードは結果ごと除外される" do
    community_results = search_jimoty_member(jimoty_html_with_first_title_href("javascript:alert(1)"))

    assert_equal 2, community_results.size
    assert_not_includes community_results.map { |result| result[:name] }, FIRST_JIMOTY_TITLE
    assert community_results.all? { |result| result[:url].start_with?("https://") }
  end

  test "url が data: のカードは結果ごと除外される" do
    community_results = search_jimoty_member(jimoty_html_with_first_title_href("data:text/html,<script>alert(1)</script>"))

    assert_equal 2, community_results.size
    assert_not_includes community_results.map { |result| result[:name] }, FIRST_JIMOTY_TITLE
  end

  test "url が http のカードは従来どおり残る" do
    community_results = search_jimoty_member(jimoty_html_with_first_title_href("http://jmty.jp/miyagi/com-fri/article-19zddu"))

    assert_equal 3, community_results.size
    assert_equal "http://jmty.jp/miyagi/com-fri/article-19zddu", community_results.first[:url]
  end

  test "url が https のカードは従来どおり残る" do
    community_results = search_jimoty_member(research_fixture("jimoty_member"))

    assert_equal 3, community_results.size
    assert_equal "https://jmty.jp/miyagi/com-fri/article-19zddu", community_results.first[:url]
  end

  test "imageUrl が javascript: なら nil になり、結果は残る" do
    community_results = search_campfire(campfire_html_with_first_image_src("javascript:alert(1)"))

    assert_equal 3, community_results.size
    assert_nil community_results.first[:imageUrl]
    assert community_results.first[:name].present?
    assert community_results[1][:imageUrl].start_with?("https://")
  end

  test "imageUrl が data: なら nil になり、結果は残る" do
    community_results = search_campfire(campfire_html_with_first_image_src("data:image/svg+xml,<svg onload=alert(1)>"))

    assert_equal 3, community_results.size
    assert_nil community_results.first[:imageUrl]
  end

  test "imageUrl が http なら従来どおり通る" do
    community_results = search_campfire(campfire_html_with_first_image_src("http://static.camp-fire.jp/a.jpeg"))

    assert_equal "http://static.camp-fire.jp/a.jpeg", community_results.first[:imageUrl]
  end
end
