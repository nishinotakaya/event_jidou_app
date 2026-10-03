module Research
  # Meetup（meetup.com）の交流会検索。AI／スタートアップ系のテック交流会が拾える
  # （2026-09-12 実測「AI」: Vibe Coding & Tech Networking in Shibuya など）。
  #
  # - JSON-LD（schema.org Event）を読む。1リクエストで最大32件
  # - location は必須。省くとアクセス元IPで地域が変わり、Heroku（米国）だけ別地域の結果になる
  # - Meetup の地域は都道府県ではなく都市なので LOCATION_SLUGS で読み替える。未選択時は東京周辺
  # - ページ送りは無い（無限スクロール）ので、代わりに地域ごとの1リクエストを並列で投げる（1件約1.8秒）
  # - location.address が空文字で返るため、会場欄には検索した地域を入れる
  # - 同じ理由で filter_by_location は通さない（会場テキストが無く、英語名のイベントが全部落ちる）
  class MeetupService < BaseService
    SITE_KEY = "meetup".freeze
    SITE_LABEL = "Meetup".freeze
    BASE_URL = "https://www.meetup.com".freeze
    FIND_PATH = "/find/".freeze

    # LOCATION_ALIASES のキー（都道府県）→ Meetup の地域スラッグ（都市）
    LOCATION_SLUGS = {
      "東京" => "jp--Tokyo",
      "神奈川" => "jp--Yokohama",
      "千葉" => "jp--Chiba",
      "埼玉" => "jp--Saitama",
      "大阪" => "jp--Osaka",
      "京都" => "jp--Kyoto",
      "兵庫" => "jp--Kobe",
      "愛知" => "jp--Nagoya",
      "福岡" => "jp--Fukuoka",
      "北海道" => "jp--Sapporo",
      "沖縄" => "jp--Naha"
    }.freeze

    DEFAULT_LOCATION = "東京".freeze
    ONLINE_LOCATION = "online".freeze

    # 1回分の検索条件。オンラインは地域ではなく eventType で指定する。
    Query = Struct.new(:location_slug, :online, :venue_label) do
      alias_method :online?, :online
    end

    def search(keyword, locations = [])
      fetches = queries(locations).map { |query| fetch_in_background(keyword, query) }
      # 隣接する地域は同じイベントを返す（横浜で検索すると東京のイベントが混ざる）ので重複を除く
      fetches.flat_map(&:value).uniq { |result| result[:url] }
    end

    private

    # Thread#value は地域ごとの失敗をそのまま呼び出し元へ投げ直す。サイト単位の失敗として
    # ResearchController に拾わせたいので、二重に記録されないよう Ruby 側の自動出力だけ止める。
    def fetch_in_background(keyword, query)
      Thread.new { fetch_events(keyword, query) }.tap { |thread| thread.report_on_exception = false }
    end

    def queries(locations)
      selected = locations.presence || [ DEFAULT_LOCATION ]
      selected.filter_map { |location| build_query(location) }.uniq
    end

    def build_query(location)
      return Query.new(LOCATION_SLUGS[DEFAULT_LOCATION], true, "オンライン") if location == ONLINE_LOCATION

      slug = LOCATION_SLUGS[location]
      slug && Query.new(slug, false, "#{location}周辺")
    end

    def fetch_events(keyword, query)
      parse_search_page(http_get(search_url(keyword, query)), query)
    end

    def search_url(keyword, query)
      params = { keywords: keyword, location: query.location_slug, source: "EVENTS" }
      params[:eventType] = "online" if query.online?
      "#{BASE_URL}#{FIND_PATH}?#{params.to_query}"
    end

    def parse_search_page(html, query)
      each_json_ld_event(parse_html(html)).filter_map { |event| build_event_result(event, query) }
    end

    def build_event_result(event, query)
      url = event["url"].to_s
      return nil if url.empty?

      build_result(
        title: event["name"],
        url: url,
        starts_at: parse_iso8601_datetime(event["startDate"]),
        datetime_text: format_datetime_text(event["startDate"]),
        venue: query.venue_label,
        organizer: event.dig("organizer", "name"),
        image_url: absolute_image_url(event["image"]),
      )
    end

    # 画像が未設定のイベントは "/images/fallbacks/..." という相対パスで返ってくる
    def absolute_image_url(image)
      return nil if image.blank?

      image.start_with?("/") ? "#{BASE_URL}#{image}" : image
    end
  end
end
