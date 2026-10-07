module Research
  # PARTY☆PARTY（www.partyparty.jp、IBJ 運営）の婚活パーティー・街コン検索。
  #
  # - JSON-LD（schema.org Event）だけ読む。1ページ27件、日時・会場・都道府県・画像まで揃う
  # - キーワードのパラメータ名に注意。画面の検索フォームの input name は freeword に見えるが、
  #   GET で freeword= を渡すと黙って無視され、全件（3,139件）が返ってくる。
  #   実際に効くのは member_party_detail_search[freeword]（2026-10-07 実測。
  #   「ボルダリング」1件・「スポーツ」17件・「スポーツ 観戦」5件で、複数語は AND）
  # - ページ超過は 404 ではなく Event 0件の 200 が返るので fetch_pages がそこで止まる
  # - startDate は "2026-10-07T14:00+09:00" のように秒が無い。parse_iso8601_datetime が
  #   Time.parse にフォールバックして読める
  # - オンライン開催は location が VirtualLocation（会場名も住所も無い）。venue を「オンライン」にして、
  #   地域の「オンライン」絞り込み（filter_by_location の online エイリアス）に掛かるようにする
  # - performer.name には「IBJ Matching … のスタッフ」のような運営の定型文が入るため、主催としては使わない
  # - 地域はサイト側で絞れないので filter_by_location で後段フィルタする
  class PartypartyService < BaseService
    SITE_KEY = "partyparty".freeze
    SITE_LABEL = "PARTY☆PARTY".freeze
    SEARCH_URL = "https://www.partyparty.jp/party_detail_search/search".freeze
    KEYWORD_PARAMETER = "member_party_detail_search%5Bfreeword%5D".freeze
    ONLINE_VENUE = "オンライン".freeze

    def search(keyword, locations = [])
      fetched_events = fetch_pages do |page_number|
        parse_search_page(http_get("#{SEARCH_URL}?#{KEYWORD_PARAMETER}=#{CGI.escape(keyword)}&page=#{page_number}"))
      end
      filter_by_location(fetched_events, locations)
    end

    private

    def parse_search_page(html)
      each_json_ld_event(parse_html(html)).filter_map { |event| build_event_result(event) }
    end

    def build_event_result(event)
      url = event["url"].to_s.strip
      # 外部 JSON-LD 由来の不正な url（javascript: 等）を結果に流さず、その 1 件だけ捨てる
      return nil unless http_url?(url)

      place = event["location"].is_a?(Hash) ? event["location"] : {}
      online = place["@type"] == "VirtualLocation"
      address = place["address"]
      organizer = event["organizer"]
      # image は文字列でも配列でも来うる。http(s) でなければ画像だけ捨てる
      image_url = Array(event["image"]).first

      build_result(
        # 名前の途中に生の改行が入っているイベントがあるので、空白を畳んで1行にする
        title: event["name"].to_s.squish,
        url: url,
        starts_at: parse_iso8601_datetime(event["startDate"]),
        datetime_text: format_datetime_text(event["startDate"]),
        venue: online ? ONLINE_VENUE : place["name"],
        address: online || !address.is_a?(Hash) ? nil : address["addressRegion"],
        organizer: organizer.is_a?(Hash) ? organizer["name"] : nil,
        image_url: http_url?(image_url) ? image_url : nil
      )
    end
  end
end
