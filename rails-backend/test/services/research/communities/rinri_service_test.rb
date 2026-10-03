require "test_helper"

# 倫理法人会（47 都道府県）。一覧 1 ページを 1 回だけ取得し、キーワード（団体名）と地域（住所）で絞る（HTTP は打たない）
class RinriServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  LIST_URL = "https://www.rinri-jpn.or.jp/houjin/list/".freeze
  GENERAL_KEYWORD = "経営者 交流会".freeze

  def service_class
    Research::Communities::RinriService
  end

  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("rinri") ])
    [ service.search(keyword, locations), requested_urls ]
  end

  def names_of(community_results)
    community_results.map { |result| result[:name] }
  end

  test "SITE_KEY は rinri" do
    assert_equal "rinri", service_class::SITE_KEY
  end

  test "団体名に一致するキーワードなら name・url・area・description に変換する" do
    community_results, = search_with("倫理法人会")

    assert_equal 4, community_results.size
    first_result = community_results.first
    assert_community_result_shape(first_result, service_class)
    assert_equal "北海道倫理法人会", first_result[:name]
    assert_equal "http://www.hokkaido-rinri.jp/", first_result[:url]
    assert_includes first_result[:area], "北海道札幌市中央区北７条西１７－３"
    assert_not_includes first_result[:area], "TEL"
    assert first_result[:description].start_with?("TEL")
    assert_includes first_result[:description], "011-213-7551"
  end

  test "一覧は 1 ページを 1 回だけ取得し、キーワードは URL に入れない" do
    _, requested_urls = search_with("倫理法人会")

    assert_equal [ LIST_URL ], requested_urls
  end

  test "地域未選択でキーワードが団体名に一致しなければ落とす" do
    community_results, = search_with(GENERAL_KEYWORD)

    assert_equal [], community_results
  end

  test "地域未選択でキーワードが団体名に部分一致するものだけ残す" do
    community_results, = search_with("東京")

    assert_equal [ "東京都倫理法人会" ], names_of(community_results)
  end

  test "地域を選べば、キーワード不一致でもその地域の団体は残る" do
    community_results, = search_with(GENERAL_KEYWORD, %w[東京])

    assert_equal [ "東京都倫理法人会" ], names_of(community_results)
    assert_equal "http://www.tokyo-rinri.net/", community_results.first[:url]
    assert_includes community_results.first[:area], "千代田区神田錦町"
    assert_includes community_results.first[:description], "03-6811-7840"
  end

  test "地域あり・キーワード不一致では他県の団体は落ちる" do
    community_results, = search_with(GENERAL_KEYWORD, %w[大阪])

    assert_equal [ "大阪府倫理法人会" ], names_of(community_results)
  end

  test "地域ありでキーワードが他県の団体名に一致すればそれも残る" do
    community_results, = search_with("大阪", %w[東京])

    assert_equal %w[東京都倫理法人会 大阪府倫理法人会], names_of(community_results)
  end

  test "複数地域はいずれかの地域の団体が残る" do
    community_results, = search_with(GENERAL_KEYWORD, %w[東京 神奈川])

    assert_equal %w[東京都倫理法人会 神奈川県倫理法人会], names_of(community_results)
  end

  test "住所に都道府県名が無くても市区の別名で地域判定する（横浜市→神奈川）" do
    community_results, = search_with(GENERAL_KEYWORD, %w[神奈川])

    assert_equal [ "神奈川県倫理法人会" ], names_of(community_results)
  end

  test "ページが空なら 0 件" do
    service = service_class.new
    stub_http_get(service, [ "" ])

    assert_equal [], service.search("倫理法人会", [])
  end
end
