module Research
  # こくちーずプロ（kokuchpro.com）のイベント検索。
  # 検索結果はサーバーレンダリングされた HTML（a.event_name がカードのタイトルリンク）。
  class KokuchproService < BaseService
    SITE_KEY = "kokuchpro".freeze
    SITE_LABEL = "こくちーずプロ".freeze
    SEARCH_URL = "https://www.kokuchpro.com/s/".freeze

    # 地域別検索パス /s/area-<地域名>/ の地域名（サイト側で絞り込める）
    AREA_NAMES = {
      "online" => "オンライン", "東京" => "東京都", "神奈川" => "神奈川県", "千葉" => "千葉県",
      "埼玉" => "埼玉県", "大阪" => "大阪府", "京都" => "京都府", "兵庫" => "兵庫県",
      "愛知" => "愛知県", "福岡" => "福岡県", "北海道" => "北海道", "沖縄" => "沖縄県"
    }.freeze

    def search(keyword, locations = [])
      area_names = locations.filter_map { |location| AREA_NAMES[location] }
      search_urls =
        if area_names.empty?
          [ "#{SEARCH_URL}?q=#{CGI.escape(keyword)}" ]
        else
          area_names.map { |area_name| "#{SEARCH_URL}area-#{CGI.escape(area_name)}/?q=#{CGI.escape(keyword)}" }
        end

      results = search_urls.flat_map do |search_url|
        fetch_pages { |page_number| parse_search_page(fetch_search_page(page_url(search_url, page_number))) }
      end
      results.uniq { |result| result[:url] }
    end

    # 1ページ目は素の検索URL、2ページ目以降は ?page=N を足す（既に ?q= が付いている前提）
    def page_url(search_url, page_number)
      page_number == 1 ? search_url : "#{search_url}&page=#{page_number}"
    end

    # こくちーずは検索ヒット0件のとき 404 を返す（本文は正常な0件ページ）ので空扱いにする
    def fetch_search_page(url)
      http_get(url)
    rescue RuntimeError => e
      raise unless e.message.include?("HTTP 404")

      ""
    end

    private

    def parse_search_page(html)
      document = parse_html(html)

      document.css("a.event_name").filter_map do |title_anchor|
        event_url = title_anchor["href"]
        next if event_url.blank?

        card_node = title_anchor.ancestors.find { |node| node.css(".fui-calendar").any? }
        datetime_text = card_node&.css(".fui-calendar")&.first&.parent&.text&.strip
        venue_text = card_node&.css(".fui-location")&.first&.parent&.text&.strip

        build_result(
          title: title_anchor.text,
          url: event_url,
          starts_at: parse_japanese_datetime(datetime_text),
          datetime_text: datetime_text,
          venue: venue_text,
        )
      end
    end
  end
end
