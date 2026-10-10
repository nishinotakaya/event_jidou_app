module Research
  # Event-J（www.event-j.com）の婚活パーティー検索。北関東〜千葉（柏・成田）に強い。
  #
  # - list_keyword.php?keyword= が効く（2026-10-10 実測: 「千葉」12 件、「スポーツ」で埼玉・栃木のスポーツコン、
  #   存在しない語は 0 件）。ページ送りは無く 1 ページに全件が載るので 1 回だけ取る
  # - カードは ul#ul_party > li。h3.party_title の a は「会場名」（例: パレット柏(Day Oneタワー3階)）で、
  #   イベント名は p.sub_title a[itemprop="name summary"] にある（取り違えやすい）
  # - p.party_place は市名（「柏市」）。県名は出ないので address に市名を入れる。
  #   一覧には県名が無く市名のみ。filter_by_location は市名一致に限られ、LOCATION_ALIASES に無い市
  #   （流山・我孫子など）は地域指定時に落ちる（LOCATION_ALIASES には柏・成田を入れてある）
  # - time.party_date の content は "2026-10-12T17:00" でタイムゾーンが無い。ローカル TZ で解釈されないよう
  #   JST のオフセットを付けてから読む。表示テキスト（「10月12日（月） 17:00～」）は datetime_text にそのまま使う
  # - href / 画像は detail.php?id=… / upload/party/… の相対パスなので絶対 URL にする
  class EventJService < BaseService
    SITE_KEY = "event_j".freeze
    SITE_LABEL = "Event-J".freeze
    BASE_URL = "https://www.event-j.com/".freeze
    SEARCH_URL = "#{BASE_URL}list_keyword.php".freeze

    def search(keyword, locations = [])
      fetched_events = parse_list_page(http_get("#{SEARCH_URL}?keyword=#{CGI.escape(keyword)}"))
      filter_by_location(fetched_events.uniq { |event_result| event_result[:url] }, locations)
    end

    private

    def parse_list_page(html)
      parse_html(html).css("ul#ul_party > li").filter_map { |card_node| build_event_result(card_node) }
    end

    def build_event_result(card_node)
      venue_link_node = card_node.at_css("h3.party_title a")
      url = absolute_http_url(BASE_URL, venue_link_node&.[]("href"))
      return nil unless url

      title = card_node.at_css('p.sub_title a[itemprop="name summary"]')&.text.to_s.squish
      return nil if title.empty?

      date_node = card_node.at_css("time.party_date")

      build_result(
        title: title,
        url: url,
        starts_at: parse_jst_datetime(date_node&.[]("content")),
        datetime_text: date_node&.text.to_s.squish,
        venue: venue_link_node.text.squish,
        address: card_node.at_css("p.party_place")&.text.to_s.squish,
        image_url: absolute_http_url(BASE_URL, card_node.at_css("p.party_img_box img")&.[]("src"))
      )
    end

    def parse_jst_datetime(text)
      return nil if text.blank?

      parse_iso8601_datetime("#{text.strip}#{JST_OFFSET}")
    end
  end
end
