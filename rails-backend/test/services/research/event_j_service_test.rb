require "test_helper"

# Event-J（www.event-j.com）。ul#ul_party のカードパースと、会場名/イベント名の取り違え防止・JST 解釈・地域フィルタを検証する（HTTP は打たない）
class EventJServiceTest < ActiveSupport::TestCase
  include ResearchHttpStub

  def service_class
    Research::EventJService
  end

  def search_with(keyword, locations = [])
    service = service_class.new
    requested_urls = stub_http_get(service, [ research_fixture("event_j") ])
    [ service.search(keyword, locations), requested_urls ]
  end

  def card_html(href: "detail.php?id=1", image_src: "upload/party/a.png")
    <<~HTML
      <ul id="ul_party"><li>
        <h3 class="party_title"><a href="#{href}">会場A</a></h3>
        <p class="party_img_box"><a href="#{href}"><img src="#{image_src}"></a></p>
        <p class="party_place">柏市</p>
        <time class="party_date" content="2026-10-12T17:00">10月12日（月） 17:00～</time>
        <p class="sub_title"><a href="#{href}" itemprop="name summary">テスト</a></p>
      </li></ul>
    HTML
  end

  def search_html(html)
    service = service_class.new
    stub_http_get(service, [ html ])
    service.search("千葉")
  end

  test "SITE_KEY は event_j、SITE_LABEL は Event-J" do
    assert_equal "event_j", service_class::SITE_KEY
    assert_equal "Event-J", service_class::SITE_LABEL
  end

  test "カード 3 件を取り出し、結果の形が揃っている" do
    event_results, = search_with("千葉")

    assert_equal 3, event_results.size
    event_results.each do |event_result|
      assert_equal service_class::SITE_KEY, event_result[:site]
      assert_equal service_class::SITE_LABEL, event_result[:siteLabel]
    end
  end

  test "title はイベント名（sub_title）、venue は h3 の会場名" do
    first_event = search_with("千葉")[0].first

    assert_equal "予約15名突破☆大人カジュアル一人参加中心☆思いやりがある男女編【33～52歳】", first_event[:title]
    assert_equal "パレット柏(Day Oneタワー3階)", first_event[:venue]
    assert_equal "柏市", first_event[:address]
    assert_nil first_event[:organizer]
  end

  test "url と画像の相対パスは絶対 URL になる" do
    first_event = search_with("千葉")[0].first

    assert_equal "https://www.event-j.com/detail.php?id=11614", first_event[:url]
    assert_equal "https://www.event-j.com/upload/party/2026/10/party11614_20260811023643_thumb.png", first_event[:imageUrl]
  end

  test "タイムゾーン無しの content は JST として読み、表示テキストが datetimeText になる" do
    first_event = search_with("千葉")[0].first
    starts_at = Time.iso8601(first_event[:startsAt])

    assert_equal Time.iso8601("2026-10-12T17:00:00+09:00"), starts_at
    assert_equal 9 * 3600, starts_at.utc_offset
    assert_equal "10月12日（月） 17:00～", first_event[:datetimeText]
  end

  test "href が javascript: のカードは捨てられ、href が空のカードも捨てられる" do
    assert_equal [], search_html(card_html(href: "javascript:alert(1)"))
    assert_equal [], search_html(card_html(href: ""))
  end

  test "イベント名が空のカードは捨てられる" do
    assert_equal [], search_html(card_html.sub("テスト</a></p>", "</a></p>"))
  end

  test "画像が javascript: なら画像だけ nil で結果は残る" do
    event_results = search_html(card_html(image_src: "javascript:alert(1)"))

    assert_equal 1, event_results.size
    assert_nil event_results.first[:imageUrl]
  end

  test "keyword は CGI エスケープされ、1 回だけ要求する" do
    _, requested_urls = search_with("千葉 & スポーツ")

    assert_equal [ "https://www.event-j.com/list_keyword.php?keyword=#{CGI.escape('千葉 & スポーツ')}" ], requested_urls
  end

  test "地域に千葉を選ぶと柏市・成田市とも残る" do
    event_results, = search_with("千葉", %w[千葉])

    assert_equal 3, event_results.size
  end

  test "地域に大阪を選ぶと 0 件" do
    assert_equal [], search_with("千葉", %w[大阪])[0]
  end

  test "イベント検索（ResearchController::SERVICES）に event_j として登録されている" do
    assert_equal service_class, Api::ResearchController::SERVICES["event_j"]
  end
end
