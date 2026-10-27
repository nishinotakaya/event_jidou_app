module Research
  # EVENT CONTACT（event-contact.com）の少人数 1対1トーク着席型 恋活・婚活パーティー検索。関東（東京・神奈川・千葉・埼玉・群馬・茨城）のみ。
  #
  # - 一覧ページは Vue SPA だが、裏の JSON API を認証なしで GET できる。
  #   /index.php/api/activity/index?limit=200&page=N … index.php を挟まないと SPA の HTML が返る
  # - keyword / q / name などのキーワード系も地域系も全て無視される（存在しない語でも total は変わらない）。
  #   効くのは page / limit / date だけなので、全件（約 200 件）を取って Ruby 側で絞る。
  #   limit=200 で 1〜2 ページに収まり、fetch_pages が「list が空 / 新規 URL 無し」で打ち切る
  # - 詳細ページは /event/detail/{id}（Vue Router の history モード）。一覧に URL が無いので id から組み立てる
  # - date "2026-10-28" / start "13:30" / end "14:30" はタイムゾーン無し。ローカル TZ で解釈されないよう JST のオフセットを付けて読む
  # - 画像は http:// だが https:// でも取れる。フロントは https（Vercel）なので mixed content を避けるため https に置き換える
  # - type は "1対1トーク着席型" / "１：１トーク着席型" / "1:1トーク着席型" と表記ゆれがある。
  #   キーワード検索は NFKC で全角半角を同一視するが、「1対1」と「1:1」は別の語なのでそのまま扱う
  # - m_number / w_number（男女の定員）が 0,0 のものは「不明」であって「定員 0」ではない。capacity は nil にする
  # - countyText は "東京都" のような都道府県名なので、filter_by_location の後段フィルタがそのまま効く（null の会が 1 件ある）
  class EventContactService < BaseService
    SITE_KEY = "event_contact".freeze
    SITE_LABEL = "EVENT CONTACT".freeze
    BASE_URL = "https://event-contact.com/".freeze
    LIST_URL = "#{BASE_URL}index.php/api/activity/index".freeze
    DETAIL_URL_PREFIX = "#{BASE_URL}event/detail/".freeze
    PAGE_LIMIT = 200
    ORGANIZER_NAME = "EVENT CONTACT".freeze
    # 男女合計の定員がこの人数以下なら「少人数」の会とみなす
    SMALL_GROUP_MAX_CAPACITY = 10
    SMALL_GROUP_WORD = "少人数".freeze

    def search(keyword, locations = [])
      fetched_events = fetch_pages { |page_number| parse_list_page(http_get(list_url(page_number))) }
      unique_events = fetched_events.uniq { |event_result| event_result[:url] }
      keyword_matched_events = unique_events.select { |event_result| matches_keyword?(event_result, keyword) }
      filter_by_location(keyword_matched_events, locations).map { |event_result| event_result.except(:searchableText) }
    end

    private

    def list_url(page_number)
      "#{LIST_URL}?limit=#{PAGE_LIMIT}&page=#{page_number}"
    end

    # 検索対象は件名・最寄駅・形式・住所＋少人数の語。searchableText は結果の形（build_result）に無いので、
    # パース時に一時的に持たせ、フィルタ後に取り除く（フロントへは返さない）
    def matches_keyword?(event_result, keyword)
      searchable_text = normalize_for_match(event_result[:searchableText])
      keyword.to_s.split(/[[:space:]]+/).reject(&:empty?).all? { |word| searchable_text.include?(normalize_for_match(word)) }
    end

    # 全角/半角・大文字小文字は NFKC + downcase で同一視する
    def normalize_for_match(text)
      text.to_s.unicode_normalize(:nfkc).downcase
    end

    # code が 1 以外・list が配列でないレスポンスを空配列にすると「0 件」に見えてしまうので、必ず例外にする
    def parse_list_page(body)
      return [] if body.blank?

      payload = JSON.parse(body)
      activities = payload.is_a?(Hash) && payload["data"].is_a?(Hash) ? payload["data"]["list"] : nil
      raise "EVENT CONTACT のレスポンスが想定外です（code=#{payload.is_a?(Hash) ? payload['code'].inspect : 'なし'}）" unless payload.is_a?(Hash) && payload["code"] == 1 && activities.is_a?(Array)

      activities.filter_map { |activity| build_event_result(activity) }
    end

    def build_event_result(activity)
      return nil unless activity.is_a?(Hash) && activity["id"].present?

      title = activity["name"].to_s.squish
      return nil if title.empty?

      capacity = total_capacity(activity)
      build_result(
        title: title,
        url: "#{DETAIL_URL_PREFIX}#{activity['id']}",
        starts_at: parse_iso8601_datetime(start_datetime_text(activity)),
        datetime_text: datetime_text(activity),
        venue: activity["sub_title"].to_s.squish,
        address: address_text(activity),
        organizer: ORGANIZER_NAME,
        capacity: capacity,
        participants: participant_count(activity, capacity),
        image_url: secure_image_url(activity["image"])
      ).merge(searchableText: searchable_text(activity, capacity))
    end

    # ユーザーは「少人数」「東京」で探す。タイトルに「少人数」と書いていない会も実態は男女各 2 名の少人数なので、
    # 定員から判定した語を足して拾えるようにする。定員が不明（0,0）の会には足さない
    def searchable_text(activity, capacity)
      small_group_word = capacity && capacity <= SMALL_GROUP_MAX_CAPACITY ? SMALL_GROUP_WORD : nil
      [ activity["name"], activity["sub_title"], activity["type"], activity["countyText"], activity["areaText"],
        activity["address"], small_group_word ].compact.join(" ")
    end

    def start_datetime_text(activity)
      return nil if activity["date"].blank? || activity["start"].blank?

      "#{activity['date']}T#{activity['start']}:00#{JST_OFFSET}"
    end

    # 「2026年10月28日 13:30〜14:30」。終了時刻が無ければ「〜」以降は付けない
    def datetime_text(activity)
      start_text = format_datetime_text(start_datetime_text(activity))
      return nil unless start_text

      activity["end"].present? ? "#{start_text}〜#{activity['end']}" : start_text
    end

    def address_text(activity)
      [ "#{activity['countyText']}#{activity['areaText']}", activity["address"].to_s.squish ].reject(&:blank?).join(" ")
    end

    def total_capacity(activity)
      capacity = activity["m_number"].to_i + activity["w_number"].to_i
      capacity.positive? ? capacity : nil
    end

    def participant_count(activity, capacity)
      return nil unless capacity

      count = capacity - activity["m_surplus"].to_i - activity["w_surplus"].to_i
      count.negative? ? nil : count
    end

    def secure_image_url(image)
      secure_url = image.to_s.strip.sub(/\Ahttp:/, "https:")
      http_url?(secure_url) ? secure_url : nil
    end
  end
end
