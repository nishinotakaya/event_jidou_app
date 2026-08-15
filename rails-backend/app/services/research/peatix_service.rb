module Research
  # Peatix（peatix.com）のイベント検索。
  # 検索ページが内部で使う JSON API（/search/events）を直接叩く。
  #
  # ⚠️ Peatix は Heroku などデータセンターIPからのアクセスに対し 200 + 空ボディを返してブロックする。
  # そのため本番ではブラウザから直接 API を叩き（CORS 許可済み）、そのレスポンスを
  # Api::ResearchController#normalize 経由で parse_response に渡してくる経路がある。
  class PeatixService < BaseService
    SITE_KEY = "peatix".freeze
    SITE_LABEL = "Peatix".freeze
    SEARCH_URL = "https://peatix.com/search/events".freeze
    PAGE_SIZE = 50

    # ブラウザ側フォールバックが叩く検索APIのURL（ページ分まとめて返す）
    def self.search_api_urls(keyword)
      (1..MAX_SEARCH_PAGES).map do |page_number|
        "#{SEARCH_URL}?q=#{CGI.escape(keyword)}&country=JP&p=#{page_number}&size=#{PAGE_SIZE}"
      end
    end

    def search(keyword, locations = [])
      page_urls = self.class.search_api_urls(keyword)
      fetch_pages(max_pages: page_urls.size) do |page_number|
        parse_response(
          http_get(
            page_urls[page_number - 1],
            { "X-Requested-With" => "XMLHttpRequest", "Accept" => "application/json" }
          ),
          locations
        )
      end
    end

    # 検索APIのレスポンス本文（JSON文字列）を共通フォーマットに整形する。
    def parse_response(body, locations = [])
      events = JSON.parse(body).dig("json_data", "events") || []

      results = events.filter_map do |event|
        event_id = event["id"]
        next if event_id.blank?

        # オンラインイベントの会場は内部プレースホルダ（xxxonlineeventxxx）で返ってくる
        venue_name = event["venue_name"].to_s
        venue_name = "オンライン" if venue_name.match?(/online/i)

        build_result(
          title: event["name"],
          url: "https://peatix.com/event/#{event_id}",
          starts_at: parse_peatix_datetime(event["datetime"]),
          datetime_text: event["datetime"],
          venue: venue_name,
          address: event["address"],
          organizer: event.dig("organizer", "nickname"),
          image_url: event["cover"],
        )
      end
      filter_by_location(results, locations)
    end

    private

    # "2026-08-23 10:00:00 +0900" 形式
    def parse_peatix_datetime(text)
      return nil if text.blank?

      Time.strptime(text, "%Y-%m-%d %H:%M:%S %z")
    rescue ArgumentError
      nil
    end
  end
end
