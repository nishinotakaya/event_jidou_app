module Research
  # ジモティー（jmty.jp）のイベント検索。
  # 全国のイベントカテゴリ（/all/eve）をキーワード検索した HTML をパースする。
  class JimotyService < BaseService
    SITE_KEY = "jimoty".freeze
    SITE_LABEL = "ジモティー".freeze
    SEARCH_URL = "https://jmty.jp/all/eve".freeze

    def search(keyword, locations = [])
      results = fetch_pages do |page_number|
        # ジモティーは最終ページを超えると 404 を返すので、404 は「もう無い」として扱う
        parse_search_page(http_get_allowing_not_found("#{SEARCH_URL}?keyword=#{CGI.escape(keyword)}&page=#{page_number}"))
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
          starts_at: parse_japanese_datetime(date_text),
          datetime_text: date_text,
          venue: card_node.at_css(".p-item-secondary-important a")&.text&.squish,
          image_url: card_node.at_css("img.p-item-image")&.attr("src"),
        )
      end
    end
  end
end
