module Research
  # ジモティー（jmty.jp）のイベント検索。
  # 全国のイベントカテゴリ（/all/eve）をキーワード検索した HTML をパースする。
  class JimotyService < BaseService
    SITE_KEY = "jimoty".freeze
    SITE_LABEL = "ジモティー".freeze
    SEARCH_URL = "https://jmty.jp/all/eve".freeze

    def search(keyword, locations = [])
      results = fetch_pages do |page_number|
        parse_search_page(http_get("#{SEARCH_URL}?keyword=#{CGI.escape(keyword)}&page=#{page_number}"))
      end
      filter_by_location(results, locations)
    end

    private

    def parse_search_page(html)
      document = parse_html(html)

      document.css("li.p-articles-list-item").filter_map do |card_node|
        title_anchor = card_node.at_css(".p-item-title a")
        next unless title_anchor

        date_text = card_node.at_css(".p-item-most-important")&.text&.squish

        build_result(
          title: title_anchor.text,
          url: title_anchor["href"],
          starts_at: parse_jimoty_date(date_text),
          datetime_text: date_text,
          venue: card_node.at_css(".p-item-secondary-important a")&.text&.squish,
          image_url: card_node.at_css("img.p-item-image")&.attr("src"),
        )
      end
    end

    # 「開催日:8/26」形式（年なし）。今日より過去の月日なら翌年扱いにする。
    def parse_jimoty_date(text)
      match = text&.match(%r{(\d{1,2})/(\d{1,2})})
      return nil unless match

      today = Time.now.getlocal(JST_OFFSET).to_date
      date = Date.new(today.year, match[1].to_i, match[2].to_i)
      date = date.next_year if date < today
      Time.new(date.year, date.month, date.day, 0, 0, 0, JST_OFFSET)
    rescue ArgumentError
      nil
    end
  end
end
