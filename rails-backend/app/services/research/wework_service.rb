module Research
  # WeWork（wework.co.jp/events）のセミナー・イベント一覧。
  # フレキシブルオフィスの WeWork が各拠点で開催する交流会・ピッチ・ビジネスセミナーが載る。
  #
  # ■ 取得方法
  #   Next.js の SSR ページなので、HTML 中の <script id="__NEXT_DATA__"> に一覧が JSON で丸ごと入っている。
  #   DOM をスクレイプするより壊れにくいのでこちらを読む（本文・拠点・サムネまで揃っている）。
  #   ページ送りはクエリではなくパス（/events/page/2）。?page=2 は無視されて1ページ目が返るので注意。
  #
  # ■ キーワードについて
  #   サイト側にフリーワード検索が無い（絞れるのはカテゴリのみ）ので、取得後にこちらで突き合わせる。
  #   突き合わせ先はタイトル・カテゴリ・会場までで、本文は含めない。
  #   本文は数千字の告知文で「交流会」「AI」がほぼ必ず出てくるため、含めると
  #   どんなキーワードでも掲載中のイベントが全部ヒットして、キーワードの意味が無くなる（2026-08-27 実測）。
  #   カテゴリ（交流会・マッチング／ビジネスセミナー／ビジネスピッチ等）を対象に含めているので、
  #   「交流会」のようにタイトルには出ない語でも狙ったイベントは拾える。
  class WeworkService < BaseService
    SITE_KEY = "wework".freeze
    SITE_LABEL = "WeWork".freeze
    BASE_URL = "https://wework.co.jp".freeze
    EVENTS_PATH = "/events".freeze

    # 一覧は開催日の新しい順に1ページ9件。開催予定は先頭に固まっているので、
    # 過去のイベントに到達した時点で打ち切る（collect_listings 参照）。3ページ＝27件は保険。
    MAX_LIST_PAGES = 3

    # 本文から会場を拾う行（「■ 場所：WeWork 神谷町トラストタワー　23階ラウンジ」）。
    # event_location の拠点名は英語表記（WeWork Kamiyacho Trust Tower）のことがあり、
    # そのままだと場所での絞り込みが効かないので、日本語表記が入るこの行も住所として持たせる。
    LOCATION_LINE = /\A[\s■●◆]*(?:開催)?(?:場所|会場|開催地|住所)\s*[:：]\s*(.+)\z/

    # 一覧1件分。キーワード照合に使うテキストは結果 Hash に混ぜたくない（フロントに渡るキーは
    # build_result のものだけに保ちたい）ので、照合用テキストだけ横に持つ。
    Listing = Struct.new(:result, :searchable_text)

    def search(keyword, locations = [])
      matched_results = filter_by_keyword(collect_listings, keyword)
      filter_by_location(matched_results, locations)
    end

    private

    # 開催日の新しい順に並ぶ一覧を、検索対象の期間より前のイベントが出てくるまで辿る。
    # 実測では開催予定は1ページ目に収まるので、通常はリクエスト1回で終わる。
    def collect_listings
      collected_listings = []

      (1..MAX_LIST_PAGES).each do |page_number|
        page_listings = parse_list_page(http_get(list_page_url(page_number)))
        break if page_listings.empty?

        collected_listings.concat(page_listings)
        break if page_listings.any? { |listing| before_range?(listing.result) }
      end
      collected_listings
    end

    def list_page_url(page_number)
      page_number <= 1 ? "#{BASE_URL}#{EVENTS_PATH}" : "#{BASE_URL}#{EVENTS_PATH}/page/#{page_number}"
    end

    def before_range?(result)
      event_date = DateRange.event_date(result)
      event_date.present? && event_date < date_range.from_date
    end

    def parse_list_page(html)
      next_data = parse_html(html).at_css("#__NEXT_DATA__")&.text
      raise "イベントデータが見つかりません（ページ構造が変わった可能性）" if next_data.blank?

      items = JSON.parse(next_data).dig("props", "pageProps", "eventList", "items") || []
      items.filter_map { |item| build_listing(item) }
    end

    def build_listing(item)
      slug = item["slug"].to_s
      return nil if slug.empty?

      event = item["event"] || {}
      starts_at = parse_event_datetime(event["event_day"], event["event_start"])
      venue_from_description = extract_venue_from_description(event["event_description"])
      venue = joined_location_titles(event["event_location"]) || venue_from_description

      result = build_result(
        title: item["title"],
        url: "#{BASE_URL}#{EVENTS_PATH}/#{slug}",
        starts_at: starts_at,
        datetime_text: starts_at&.strftime("%Y年%-m月%-d日 %H:%M"),
        venue: venue,
        address: venue_from_description,
        organizer: SITE_LABEL,
        image_url: item.dig("thumbnail", "medium_large") || item.dig("thumbnail", "url"),
      )
      Listing.new(result, searchable_text(item, event, venue))
    end

    # event_day は "2026/09/28"、event_start は "18:00:00"（どちらも空のことがある）
    def parse_event_datetime(event_day, event_start)
      day_match = event_day.to_s.match(%r{\A(\d{4})/(\d{1,2})/(\d{1,2})\z})
      return nil unless day_match

      hour, minute = event_start.to_s.split(":")
      Time.new(day_match[1].to_i, day_match[2].to_i, day_match[3].to_i, hour.to_i, minute.to_i, 0, JST_OFFSET)
    rescue ArgumentError
      nil
    end

    def joined_location_titles(event_location)
      Array(event_location).filter_map { |location| location["title"].presence }.join(" / ").presence
    end

    def extract_venue_from_description(description)
      description.to_s.each_line do |line|
        matched = line.strip.match(LOCATION_LINE)
        return matched[1].strip if matched && matched[1].strip.present?
      end
      nil
    end

    def searchable_text(item, event, venue)
      category_names = Array(item["category"]).map { |category| category["name"] }
      [ item["title"], event["event_note"], venue, *category_names ].compact.join(" ")
    end

    # 「経営者 交流会」のように語をスペースで並べる使われ方をするため、いずれかに当たれば残す
    # （すべてを満たす条件にすると、掲載が十数件しかない WeWork ではほぼ0件になってしまう）。
    def filter_by_keyword(listings, keyword)
      terms = keyword.to_s.split(/[[:space:]]+/).reject(&:empty?).map(&:downcase)
      return listings.map(&:result) if terms.empty?

      listings.filter_map do |listing|
        text = listing.searchable_text.downcase
        listing.result if terms.any? { |term| text.include?(term) }
      end
    end
  end
end
