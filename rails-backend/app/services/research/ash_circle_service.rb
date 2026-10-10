module Research
  # 社会人サークルアッシュ（www.ya-7.com）の社会人サークルイベント検索。40〜70代中心の食事会・飲み会が多い。
  #
  # - キーワード検索もページ送りも無い。エリア別の一覧ページ（1 エリア 1 リクエスト）を取り、
  #   タイトルでキーワードを後段フィルタする（空白区切りの全語を含む AND・部分一致）
  # - エリア URL は 2026-10-10 実測。/kanagawa/ /hyogo/ /aichi/ /hokkaido/ は 404 で、
  #   神奈川は /yokohama/、兵庫は /kobe/、愛知は /nagoya/、北海道は /sapporo/、沖縄だけ /area_okinawa.php
  # - 地域が未指定（またはオンラインのみ）のときはトップページ（全国の直近 27 件）を 1 回だけ取る
  # - JSON-LD は使わない。description の引用符が未エスケープで JSON として壊れており、
  #   sanitize_json_ld でも直せない形のため、HTML の article.entry を読む
  # - タイトルは末尾に「 社会人サークルイベント」が付くので外す。「開催中止」のカードは一覧に残り続けるため捨てる
  # - 日付は time[datetime] が 2 つ並ぶ。1 つ目が日付（2026.10.10）、2 つ目が時間帯（16:00～18:00、～ は全角 U+FF5E）。
  #   datetime 属性は 2 つとも日付なので、開始時刻は 2 つ目の表示テキストから取る
  # - 会場名は一覧に出ない（venue は nil）。都道府県ラベル（例「千葉」）だけ address に入れる
  # - 画像は /eventimage/... の相対パスなので絶対 URL にする
  class AshCircleService < BaseService
    SITE_KEY = "ash_circle".freeze
    SITE_LABEL = "社会人サークルアッシュ".freeze
    TOP_URL = "https://www.ya-7.com/".freeze
    ORGANIZER_NAME = "社会人サークルアッシュ".freeze
    TITLE_SUFFIX = /\s*社会人サークルイベント\s*\z/
    CANCELLED_MARK = "開催中止".freeze
    EVENT_LINK_SELECTOR = 'a[href*="event_info.php?EventNum="]'.freeze

    AREA_PATHS = {
      "東京" => "/tokyo/",
      "神奈川" => "/yokohama/",
      "千葉" => "/chiba/",
      "埼玉" => "/saitama/",
      "大阪" => "/osaka/",
      "京都" => "/kyoto/",
      "兵庫" => "/kobe/",
      "愛知" => "/nagoya/",
      "福岡" => "/fukuoka/",
      "北海道" => "/sapporo/",
      "沖縄" => "/area_okinawa.php"
    }.freeze

    def search(keyword, locations = [])
      fetched_events = fetch_each_area(target_urls(locations))
      unique_events = fetched_events.uniq { |event_result| event_result[:url] }
      keyword_matched_events = unique_events.select { |event_result| title_matches_keyword?(event_result[:title], keyword) }
      filter_by_location(keyword_matched_events, locations)
    end

    private

    def target_urls(locations)
      area_paths = AREA_PATHS.values_at(*Array(locations)).compact
      return [ TOP_URL ] if area_paths.empty?

      area_paths.map { |area_path| URI.join(TOP_URL, area_path).to_s }
    end

    # エリア単位で取得する。失敗したエリアはログに残して飛ばし、他エリアの結果は返す。
    # ただし全エリアが失敗したときは最後の例外を再 raise する（サイト全体がブロックされているときに
    # 「0 件」に見せると、ヒット無しと区別が付かないため）
    def fetch_each_area(urls)
      last_error = nil
      failed_count = 0
      fetched_events = urls.flat_map do |url|
        parse_list_page(http_get(url))
      rescue StandardError => e
        Rails.logger.warn("[Research] #{site_key} #{url} の取得に失敗: #{e.class} #{e.message}")
        last_error = e
        failed_count += 1
        []
      end
      raise last_error if last_error && failed_count == urls.size

      fetched_events
    end

    # 空白区切りの全語がタイトルに含まれること（AND・部分一致）。キーワードが空なら全件。
    # 全角/半角（「50代」と「５０代」）・大文字小文字は NFKC + downcase で同一視する
    def title_matches_keyword?(title, keyword)
      normalized_title = normalize_for_match(title)
      keyword.to_s.split(/[[:space:]]+/).reject(&:empty?).all? { |word| normalized_title.include?(normalize_for_match(word)) }
    end

    def normalize_for_match(text)
      text.to_s.unicode_normalize(:nfkc).downcase
    end

    def parse_list_page(html)
      parse_html(html).css("article.entry").filter_map { |card_node| build_event_result(card_node) }
    end

    def build_event_result(card_node)
      url = absolute_http_url(TOP_URL, card_node.at_css(EVENT_LINK_SELECTOR)&.[]("href"))
      return nil unless url

      title = card_node.at_css("div.event_list_title")&.text.to_s.sub(TITLE_SUFFIX, "").squish
      return nil if title.empty? || title.include?(CANCELLED_MARK)

      info_node = card_node.at_css("div.f-left_inner_three")
      date_node, time_range_node = info_node ? info_node.css("time[datetime]").to_a : []
      datetime_text = [ date_node, time_range_node ].compact.map { |node| node.text.squish }.join(" ")

      build_result(
        title: title,
        url: url,
        starts_at: build_starts_at(date_node, time_range_node),
        datetime_text: datetime_text,
        address: info_node&.at_css("> div")&.text.to_s.squish,
        organizer: ORGANIZER_NAME,
        image_url: absolute_http_url(TOP_URL, card_node.at_css("picture img")&.[]("src"))
      )
    end

    # 1 つ目の datetime 属性（日付）+ 2 つ目の開始時刻を JST で組み立てる。時刻が読めなければ 00:00
    def build_starts_at(date_node, time_range_node)
      date_text = date_node&.[]("datetime").to_s.strip
      return nil if date_text.empty?

      time_match = time_range_node&.text.to_s.match(/(\d{1,2}):(\d{2})/)
      start_time = time_match ? format("%02d:%s", time_match[1].to_i, time_match[2]) : "00:00"
      parse_iso8601_datetime("#{date_text}T#{start_time}#{JST_OFFSET}")
    end
  end
end
