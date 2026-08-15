module Research
  # e-venz（イベンツ / e-venz.com）の異業種交流会・ビジネス交流会一覧。
  # 一覧ページに schema.org の Event が JSON-LD で埋め込まれているのでそれを読む。
  #
  # サイト側にフリーワード検索が無く、かつ「異業種交流会」カテゴリ自体が探しているジャンルそのものなので、
  # キーワードでは絞らずカテゴリ全件を返す（キーワード一致だけに絞ると 60件→12件 まで落ち、
  # 「カフェ会形式の交流会」など本来見たいイベントが消えるため）。場所指定だけ効かせる。
  class EvenzService < BaseService
    SITE_KEY = "evenz".freeze
    SITE_LABEL = "e-venz".freeze
    CATEGORY_URL = "https://e-venz.com/events/business".freeze

    # 場所キー → e-venz のエリアスラッグ（/events/business+tokyo/ 形式）。
    # オンライン開催のエリアページは存在しないため、"online" は全国ページ＋テキスト絞り込みで扱う。
    AREA_SLUGS = {
      "東京" => "tokyo", "神奈川" => "kanagawa", "千葉" => "chiba", "埼玉" => "saitama",
      "大阪" => "osaka", "京都" => "kyoto", "兵庫" => "hyogo", "愛知" => "aichi",
      "福岡" => "fukuoka", "北海道" => "hokkaido", "沖縄" => "okinawa"
    }.freeze

    def search(_keyword, locations = [])
      fetch_results(locations).uniq { |result| result[:url] }
    end

    private

    # エリアページがある場所はサイト側で絞り、無い場所（オンライン等）は全国ページをテキストで絞る。
    def fetch_results(locations)
      return parse_category(category_url) if locations.blank?

      area_results = locations.filter_map { |location| AREA_SLUGS[location] }
                              .flat_map { |area_slug| parse_category(category_url(area_slug)) }
      other_locations = locations.reject { |location| AREA_SLUGS.key?(location) }
      return area_results if other_locations.empty?

      area_results + filter_by_location(parse_category(category_url), other_locations)
    end

    def category_url(area_slug = nil)
      area_slug ? "#{CATEGORY_URL}+#{area_slug}/" : "#{CATEGORY_URL}/"
    end

    # カテゴリ一覧を複数ページ分まとめて取得する
    def parse_category(url)
      fetch_pages { |page_number| parse_events(http_get("#{url}?page=#{page_number}")) }
    end

    def parse_events(html)
      each_json_ld_event(parse_html(html)).filter_map do |event|
        event_url = event["url"].presence || event.dig("offers", 0, "url")
        next if event_url.blank?

        place = event["location"] || {}
        address = place.dig("address", "streetAddress")
        region = place.dig("address", "addressRegion")

        build_result(
          # JSON-LD 内の文字列は HTML エスケープされたまま（&amp; など）なので戻す
          title: CGI.unescapeHTML(event["name"].to_s),
          url: event_url,
          starts_at: parse_iso8601_datetime(event["startDate"]),
          datetime_text: format_datetime_text(event["startDate"]),
          venue: place["name"],
          address: [ region, address ].compact_blank.uniq.join(" "),
          organizer: event.dig("organizer", "name"),
          image_url: event["image"],
        )
      end
    end
  end
end
