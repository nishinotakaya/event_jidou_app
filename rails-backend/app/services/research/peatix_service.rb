module Research
  # Peatix（peatix.com）のイベント検索。経営者交流会のヒット数が最も多い（「経営者 交流会」で 752 件）。
  # 検索ページが内部で使う JSON API（/search/events）を直接叩く。HTML パースより壊れにくい。
  # ※ X-Requested-With を付けないと JSON ではなく HTML が返るので必須。
  #
  # ⚠️ 本番（Heroku）からは 200 + 空ボディで弾かれる（データセンターIPブロック）。
  # ただしこの検索APIは access-control-allow-origin: * かつ preflight で X-Requested-With を許可しており、
  # ブラウザ（＝ユーザーの回線）からなら取得できる。そこで本番では、
  #
  #   ResearchController#search が失敗を検知
  #     → browserFallbacks（search_api_urls）をフロントへ返す
  #     → フロントがブラウザから直接 fetch
  #     → 本文を Api::ResearchController#normalize に POST
  #     → ここの parse_response でサーバー側と同じ整形をかける
  #
  # という経路で救っている。整形ロジックを JS に写経しないための parse_response 公開である。
  class PeatixService < BaseService
    SITE_KEY = "peatix".freeze
    SITE_LABEL = "Peatix".freeze
    SEARCH_URL = "https://peatix.com/search/events".freeze
    # 1リクエストで取れる件数。50 までは正常に返ることを実測済み
    PAGE_SIZE = 50

    # ブラウザ側フォールバックが叩く検索APIのURL。
    # サーバー側と件数を揃えるため、1ページ目だけでなく MAX_SEARCH_PAGES 分まとめて渡す。
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
    # サーバー取得・ブラウザ取得のどちらの経路もここを通す（＝整形の実装は1つだけ）。
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
