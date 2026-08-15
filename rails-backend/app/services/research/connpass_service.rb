module Research
  # connpass（connpass.com）のイベント検索。
  # 検索結果はサーバーレンダリングされた HTML（div.event_list が1イベント）。
  # start_from で今日以降に絞る（デフォルトの並びが開催日昇順なので直近が先頭に来る）。
  class ConnpassService < BaseService
    SITE_KEY = "connpass".freeze
    SITE_LABEL = "connpass".freeze
    SEARCH_URL = "https://connpass.com/search/".freeze

    # 検索フォームの prefectures セレクトの値（サイト側で絞り込める）
    PREFECTURE_PARAMS = {
      "online" => "online", "東京" => "tokyo", "神奈川" => "kanagawa", "千葉" => "chiba",
      "埼玉" => "saitama", "大阪" => "osaka", "京都" => "kyoto", "兵庫" => "hyogo",
      "愛知" => "aichi", "福岡" => "fukuoka", "北海道" => "hokkaido", "沖縄" => "okinawa"
    }.freeze

    def search(keyword, locations = [])
      start_from = Time.now.getlocal(JST_OFFSET).strftime("%Y/%m/%d")
      url = "#{SEARCH_URL}?q=#{CGI.escape(keyword)}&start_from=#{CGI.escape(start_from)}"
      locations.filter_map { |location| PREFECTURE_PARAMS[location] }.each do |prefecture_param|
        url += "&prefectures=#{prefecture_param}"
      end
      fetch_pages { |page_number| parse_search_page(http_get("#{url}&page=#{page_number}")) }
    end

    private

    def parse_search_page(html)
      document = parse_html(html)

      document.css("div.event_list").filter_map do |event_node|
        title_anchor = event_node.at_css("p.event_title a")
        next unless title_anchor

        starts_at = parse_connpass_dtstart(event_node)
        amount_text = event_node.at_css("p.event_participants .amount")&.text&.strip
        participants, capacity = parse_participants(amount_text)

        build_result(
          title: title_anchor.text,
          url: title_anchor["href"],
          starts_at: starts_at,
          datetime_text: starts_at&.strftime("%Y年%-m月%-d日 %H:%M"),
          venue: event_node.at_css("p.event_place")&.text&.strip,
          organizer: event_node.at_css("p.event_owner a.image_link")&.text&.strip,
          participants: participants,
          capacity: capacity,
          image_url: event_node.at_css("p.event_thumbnail img.photo")&.attr("src"),
        )
      end
    end

    # <span class="dtstart"><span class="value-title" title="2026-08-20T10:00:00Z"></span></span>
    def parse_connpass_dtstart(event_node)
      iso_text = event_node.at_css(".dtstart .value-title")&.attr("title")
      return nil if iso_text.blank?

      Time.iso8601(iso_text).getlocal(JST_OFFSET)
    rescue ArgumentError
      nil
    end

    # "12/50" のような参加者数表記
    def parse_participants(amount_text)
      match = amount_text&.match(%r{(\d+)\s*/\s*(\d+)})
      return [ nil, nil ] unless match

      [ match[1].to_i, match[2].to_i ]
    end
  end
end
