require "test_helper"

# ピア街コン（pia-machicon.piary.jp）。検索結果カードの HTML パースと、おすすめ枠の除外・地域フィルタ・ページ打ち切りを検証する（HTTP は打たない）
class PiaMachiconServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  def service_class
    Research::PiaMachiconService
  end

  # 1 ページ目にフィクスチャ、2 ページ目以降は空。要求された URL も返す。
  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("pia_machicon") ])
    [ service.search(keyword, locations), requested_urls ]
  end

  def card_html(href:, image: true)
    image_tag = image ? '<img src="/html/upload/a.webp" class="recommendEvent__cont--mainImg">' : ""
    <<~HTML
      <section class="searchResult__list"><section class="recommendEvent__cont">
        #{href.nil? ? '<a class="recommendEvent__cont--link">' : %(<a href="#{href}" class="recommendEvent__cont--link">)}#{image_tag}</a>
        <h3 class="title-fav__wrap--title">テスト</h3>
        <p class="recommendEvent__cont--date"><span class="recommendEvent__cont--date--pref">東京都</span> 10月12日(月) 16:00〜</p>
      </section></section>
    HTML
  end

  def search_html(html)
    service = service_class.new
    stub_http_get(service, [ html ])
    service.search("スポーツ")
  end

  test "href に空白・日本語を含むカードは例外にならず絶対 URL になる" do
    event_results = search_html(card_html(href: "/products/detail/街コン 1"))

    assert_equal 1, event_results.size
    assert_equal "https://pia-machicon.piary.jp/products/detail/%E8%A1%97%E3%82%B3%E3%83%B3%201", event_results.first[:url]
  end

  test "既に % エンコード済みの href は二重エンコードされずそのまま返る" do
    href = "https://pia-machicon.piary.jp/products/detail/1?tag=%E3%82%B9"
    event_results = search_html(card_html(href: href))

    assert_equal href, event_results.first[:url]
  end

  test "href が javascript: のカードは捨てられる" do
    assert_equal [], search_html(card_html(href: "javascript:alert(1)"))
  end

  test "img が無いカードは imageUrl nil で結果に残る" do
    event_results = search_html(card_html(href: "/products/detail/1", image: false))

    assert_equal 1, event_results.size
    assert_nil event_results.first[:imageUrl]
  end

  test "SITE_KEY は pia_machicon、SITE_LABEL はピア街コン" do
    assert_equal "pia_machicon", service_class::SITE_KEY
    assert_equal "ピア街コン", service_class::SITE_LABEL
  end

  test "検索結果 3 件を取り出し、結果の形が揃っている" do
    event_results, = search_with("スポーツ")

    assert_equal 3, event_results.size
    event_results.each do |event_result|
      assert_equal service_class::SITE_KEY, event_result[:site]
      assert_equal service_class::SITE_LABEL, event_result[:siteLabel]
    end
  end

  test "先頭のカードを title・url・datetimeText・address・image に割り当てる" do
    event_results, = search_with("スポーツ")
    first_event = event_results.first

    assert_equal "【スポーツの日】50代60代70代の名古屋婚活♡祝日の夕方に同世代と心あたたまる出会いを", first_event[:title]
    assert_equal "https://pia-machicon.piary.jp/products/detail/50007469", first_event[:url]
    assert_equal "10月12日(月) 16:00〜", first_event[:datetimeText]
    assert_equal "愛知県", first_event[:address]
    assert_nil first_event[:venue]
  end

  test "年の無い日時でも startsAt は 10/12 16:00（JST）になる" do
    event_results, = search_with("スポーツ")
    starts_at = Time.iso8601(event_results.first[:startsAt])

    assert_equal [ 10, 12, 16, 0 ], [ starts_at.month, starts_at.day, starts_at.hour, starts_at.min ]
    assert_equal 9 * 3600, starts_at.utc_offset
  end

  test "相対パスの画像は絶対 URL になる" do
    event_results, = search_with("スポーツ")

    assert_equal "https://pia-machicon.piary.jp/html/upload/save_image/0928135133_6ab9f2558a29b.webp", event_results.first[:imageUrl]
  end

  test "検索結果の外にあるおすすめ枠の section.recommendEvent__cont は混ざらない" do
    event_results, = search_with("スポーツ")

    assert_not_includes event_results.map { |event_result| event_result[:url] }, "https://pia-machicon.piary.jp/products/detail/50007396"
    assert_not(event_results.any? { |event_result| event_result[:title].include?("50代の集う恋活パーティー") })
  end

  test "href の無いカードは捨てる" do
    html = research_fixture("pia_machicon").gsub(/<a href="[^"]*" class="recommendEvent__cont--link">/, '<a class="recommendEvent__cont--link">')
    service = service_class.new
    stub_http_get(service, [ html ])

    assert_equal [], service.search("スポーツ")
  end

  test "keyword は CGI エスケープされ、pageno が付く。2 ページ目が空なら 3 ページ目は取りに行かない" do
    _, requested_urls = search_with("婚活 パーティー&街コン")

    assert_equal [
      "https://pia-machicon.piary.jp/products/list?keyword=#{CGI.escape('婚活 パーティー&街コン')}&pageno=1",
      "https://pia-machicon.piary.jp/products/list?keyword=#{CGI.escape('婚活 パーティー&街コン')}&pageno=2"
    ], requested_urls
  end

  test "地域に東京を選ぶと東京都のカードだけ残る" do
    event_results, = search_with("スポーツ", %w[東京])

    assert_equal [ "東京都" ], event_results.map { |event_result| event_result[:address] }
  end

  test "地域に大阪を選ぶと大阪府のカードだけ残る" do
    event_results, = search_with("スポーツ", %w[大阪])

    assert_equal [ "大阪府" ], event_results.map { |event_result| event_result[:address] }
  end

  test "地域にオンラインを選ぶと 0 件" do
    event_results, = search_with("スポーツ", %w[online])

    assert_equal [], event_results
  end

  test "1 ページ目が空なら 1 回だけ要求して空配列を返す" do
    service = service_class.new
    requested_urls = stub_http_get(service, [ "" ])

    assert_equal [], service.search("スポーツ", [])
    assert_equal 1, requested_urls.size
  end

  test "イベント検索（ResearchController::SERVICES）に pia_machicon として登録されている" do
    assert_equal service_class, Api::ResearchController::SERVICES["pia_machicon"]
  end
end
