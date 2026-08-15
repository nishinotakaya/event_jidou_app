module Research
  # Doorkeeper（doorkeeper.jp）のイベント検索。
  # 公開検索ページの HTML をパースする（API はアクセストークン必須のため使わない）。
  class DoorkeeperService < BaseService
    SITE_KEY = "doorkeeper".freeze
    SITE_LABEL = "Doorkeeper".freeze
    SEARCH_URL = "https://www.doorkeeper.jp/events".freeze

    def search(keyword, locations = [])
      results = fetch_pages do |page_number|
        parse_search_page(http_get("#{SEARCH_URL}?q=#{CGI.escape(keyword)}&page=#{page_number}"))
      end
      filter_by_location(results, locations)
    end

    private

    def parse_search_page(html)
      document = parse_html(html)

      document.css(".events-list-item-title").filter_map do |title_node|
        title_anchor = title_node.at_css("a")
        next unless title_anchor

        card_node = title_node.ancestors.find { |node| node.at_css(".events-list-item-time") }
        datetime_text = card_node&.at_css(".events-list-item-time")&.text&.squish

        build_result(
          title: title_anchor.text,
          url: title_anchor["href"],
          starts_at: parse_japanese_datetime(datetime_text),
          datetime_text: datetime_text,
          venue: card_node&.at_css(".events-list-item-venue")&.text&.squish,
          organizer: card_node&.at_css(".events-list-item-group a")&.text&.squish,
        )
      end
    end
  end
end
