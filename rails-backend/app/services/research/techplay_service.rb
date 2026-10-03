module Research
  # TechPlay（techplay.jp）のイベント検索。
  # Inertia.js の <div id="app" data-page="..."> に埋め込まれた JSON からイベント一覧を取り出す。
  class TechplayService < BaseService
    SITE_KEY = "techplay".freeze
    SITE_LABEL = "TechPlay".freeze
    SEARCH_URL = "https://techplay.jp/event".freeze

    def search(keyword, locations = [])
      html = http_get("#{SEARCH_URL}?keyword=#{CGI.escape(keyword)}")
      document = parse_html(html)

      page_json = document.at_css("#app")&.attr("data-page")
      raise "イベントデータが見つかりません（ページ構造が変わった可能性）" if page_json.blank?

      events = JSON.parse(page_json).dig("props", "events", "data") || []
      results = events.filter_map do |event|
        event_id = event["id"]
        next if event_id.blank?

        starts_at = event["started_at"] ? Time.at(event["started_at"]).getlocal(JST_OFFSET) : nil

        build_result(
          title: event["title"],
          url: "https://techplay.jp/event/#{event_id}",
          starts_at: starts_at,
          datetime_text: starts_at&.strftime("%Y年%-m月%-d日 %H:%M"),
          venue: event["place"],
          address: event["address"],
          participants: event["entered"],
          capacity: event["capacity"],
          image_url: event["thumbnail_url"],
        )
      end
      filter_by_location(results, locations)
    end
  end
end
