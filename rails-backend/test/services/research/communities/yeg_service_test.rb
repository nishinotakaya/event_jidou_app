require "test_helper"

# 商工会議所青年部（YEG）。一覧 1 ページを 1 回だけ取得し、キーワード（会議所名）と地域（都道府県）で絞る（HTTP は打たない）
class YegServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  LIST_URL = "https://www.yeg.jp/about/chambers".freeze
  GENERAL_KEYWORD = "経営者 交流会".freeze

  def service_class
    Research::Communities::YegService
  end

  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("yeg") ])
    [ service.search(keyword, locations), requested_urls ]
  end

  def names_of(community_results)
    community_results.map { |result| result[:name] }
  end

  test "SITE_KEY は yeg" do
    assert_equal "yeg", service_class::SITE_KEY
  end

  test "会議所名に一致するキーワードなら name・url・area に変換する（url は最初のリンク＝公式サイト）" do
    community_results, = search_with("八王子")

    assert_equal 1, community_results.size
    only_result = community_results.first
    assert_community_result_shape(only_result, service_class)
    assert_equal "八王子", only_result[:name]
    assert_equal "https://802yeg.jp/", only_result[:url]
    assert_equal "東京", only_result[:area]
  end

  test "一覧は 1 ページを 1 回だけ取得し、キーワードは URL に入れない" do
    _, requested_urls = search_with("八王子")

    assert_equal [ LIST_URL ], requested_urls
  end

  test "地域未選択でキーワードが会議所名に一致しなければ落とす" do
    community_results, = search_with(GENERAL_KEYWORD)

    assert_equal [], community_results
  end

  test "地域を選べば、キーワード不一致でもその都道府県の会議所は残る（複数テーブルをまたいで拾う）" do
    community_results, = search_with(GENERAL_KEYWORD, %w[東京])

    assert_equal %w[東京 八王子 町田], names_of(community_results)
    assert(community_results.all? { |result| result[:area] == "東京" })
    assert_equal [ "https://www.tokyo-cci.or.jp/seinenbu/", "https://802yeg.jp/", "https://machida-cci.or.jp/youth/" ],
                 community_results.map { |result| result[:url] }
  end

  test "地域あり・キーワード不一致では他県の会議所は落ちる" do
    community_results, = search_with(GENERAL_KEYWORD, %w[神奈川])

    assert_equal [ "横浜" ], names_of(community_results)
    assert_equal "神奈川", community_results.first[:area]
    assert_equal "https://www.yokohama-cci.or.jp/about/seinenbu/", community_results.first[:url]
  end

  test "地域ありでキーワードが他県の会議所名に一致すればそれも残る" do
    community_results, = search_with("横浜", %w[東京])

    assert_equal %w[東京 八王子 町田 横浜], names_of(community_results)
  end

  test "複数地域はいずれかの都道府県の会議所が残る" do
    community_results, = search_with(GENERAL_KEYWORD, %w[東京 神奈川])

    assert_equal %w[東京 八王子 町田 横浜], names_of(community_results)
  end

  test "都道府県見出し直後のリンクだけの段落（神奈川の Facebook）は会議所として拾わない" do
    community_results, = search_with(GENERAL_KEYWORD, %w[神奈川])

    assert_equal 1, community_results.size
  end

  test "ページが空なら 0 件" do
    service = service_class.new
    stub_http_get(service, [ "" ])

    assert_equal [], service.search("八王子", [])
  end
end
