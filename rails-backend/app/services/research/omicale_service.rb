module Research
  # オミカレ（party-calendar.net）の婚活・街コン・パーティー検索。
  #
  # - JSON-LD（schema.org Event）だけ読む。1ページ20件、日時・会場・都道府県・画像まで揃う
  # - 定員（maximumAttendeeCapacity / remainingAttendeeCapacity）は欠けているイベントが多い。
  #   参加者数は「定員 − 残り」で出せるときだけ入れ、片方でも欠ければ nil にする（推測で埋めない）
  # - 地域は検索条件に併用できないため filter_by_location で後段フィルタする
  # - 掲載は全て対面イベントなので、地域に「オンライン」を選ぶと0件になる
  class OmicaleService < BaseService
    SITE_KEY = "omicale".freeze
    SITE_LABEL = "オミカレ".freeze
    SEARCH_URL = "https://party-calendar.net/search".freeze

    def search(keyword, locations = [])
      results = fetch_pages do |page_number|
        parse_search_page(http_get("#{SEARCH_URL}?keyword=#{CGI.escape(keyword)}&page=#{page_number}"))
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
      capacity = event["maximumAttendeeCapacity"]

      build_result(
        title: event["name"],
        url: url,
        starts_at: parse_iso8601_datetime(event["startDate"]),
        datetime_text: format_datetime_text(event["startDate"]),
        venue: place["name"],
        address: place.dig("address", "addressRegion"),
        image_url: event["image"],
        capacity: capacity,
        participants: participants_count(capacity, event["remainingAttendeeCapacity"]),
      )
    end

    def participants_count(capacity, remaining)
      return nil unless capacity.is_a?(Numeric) && remaining.is_a?(Numeric)

      capacity - remaining
    end
  end
end
