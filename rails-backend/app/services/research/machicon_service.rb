module Research
  # 街コンジャパン（machicon.jp）の街コン・恋活・婚活イベント検索。
  #
  # - JSON-LD（schema.org Event）だけ読む。1ページ24件、日時・会場・都道府県・主催・画像まで揃う
  # - キーワードは s。keyword を渡すと黙って無視され、全件の新着一覧が返る（2026-09-12 実測）
  # - ページ超過は 404 ではなく Event 0件の 200 が返るので fetch_pages がそこで止まる（同日 page=99）
  # - image は常に絶対URL（同日24件すべて）なので正規化は要らない
  # - 地域は /areas/... という別系統でキーワードと併用できないため filter_by_location で後段フィルタ
  # - 掲載は全て対面イベントなので、地域に「オンライン」を選ぶと0件になる
  class MachiconService < BaseService
    SITE_KEY = "machicon".freeze
    SITE_LABEL = "街コンジャパン".freeze
    SEARCH_URL = "https://machicon.jp/search/".freeze

    def search(keyword, locations = [])
      results = fetch_pages do |page_number|
        parse_search_page(http_get("#{SEARCH_URL}?s=#{CGI.escape(keyword)}&page=#{page_number}"))
      end
      filter_by_location(results, locations)
    end

    private

    def parse_search_page(html)
      each_json_ld_event(parse_html(html)).filter_map { |event| build_event_result(event) }
    end

    def build_event_result(event)
      url = event["url"].to_s
      return nil if url.empty?

      place = event["location"].is_a?(Hash) ? event["location"] : {}

      build_result(
        title: event["name"],
        url: url,
        starts_at: parse_iso8601_datetime(event["startDate"]),
        datetime_text: format_datetime_text(event["startDate"]),
        venue: place["name"],
        address: place.dig("address", "addressRegion"),
        organizer: event.dig("organizer", "name"),
        image_url: event["image"],
      )
    end
  end
end
