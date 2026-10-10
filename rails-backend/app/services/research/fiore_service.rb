module Research
  # フィオーレパーティー（www.fiore-party.com）の個室婚活パーティー検索。
  #
  # - フリーワード検索が無い（?keyword= を渡しても無視される）。都道府県一覧ページの JSON-LD を取り、
  #   name + description でキーワードを後段フィルタする（空白区切りの全語を含む AND・部分一致）
  # - URL は /pref/pref_tokyo?pageIndex=1 のような形。該当する地域が無ければ全国の pref_all（1 ページ 18 件）
  # - 範囲外の pageIndex は 404 でも空でもなく、200 で 1 ページ目と同じ内容が返る。
  #   fetch_pages は「新しい URL が 1 件も無ければ打ち切り」なので、それで止まる（最終ページの判定を別途持たない）
  # - 地域未指定時は pref_all を最大 3 ページ（18 件 × 3 = 54 件）しか見ないので、
  #   キーワード絞り込みの母集団はその範囲に限られる
  # - JSON-LD は 1 つの <script> に Event の配列が入っている。each_json_ld_event が Array を扱える
  # - startDate は "2026/10/10 16:30:00" のスラッシュ区切りでタイムゾーンが無い。
  #   Time.parse に任せるとサーバーのローカル TZ（Heroku は UTC）で解釈されて 9 時間ずれるため、
  #   JST のオフセットを付けてから読む
  # - addressRegion は "千葉県" のような都道府県名なので、filter_by_location の後段フィルタがそのまま効く
  class FioreService < BaseService
    SITE_KEY = "fiore".freeze
    SITE_LABEL = "フィオーレパーティー".freeze
    BASE_URL = "https://www.fiore-party.com/pref/".freeze
    ALL_PREFECTURES_SLUG = "pref_all".freeze
    ORGANIZER_NAME = "フィオーレパーティー".freeze

    PREFECTURE_SLUGS = {
      "東京" => "pref_tokyo",
      "神奈川" => "pref_kanagawa",
      "千葉" => "pref_chiba",
      "埼玉" => "pref_saitama",
      "大阪" => "pref_osaka",
      "京都" => "pref_kyoto",
      "兵庫" => "pref_hyogo",
      "愛知" => "pref_aichi",
      "福岡" => "pref_fukuoka",
      "北海道" => "pref_hokkaido",
      "沖縄" => "pref_okinawa"
    }.freeze

    def search(keyword, locations = [])
      fetched_events = fetch_each_prefecture(target_slugs(locations))
      unique_events = fetched_events.uniq { |event_result| event_result[:url] }
      keyword_matched_events = unique_events.select { |event_result| matches_keyword?(event_result, keyword) }
      filter_by_location(keyword_matched_events, locations).map { |event_result| event_result.except(:searchableText) }
    end

    private

    def target_slugs(locations)
      slugs = PREFECTURE_SLUGS.values_at(*Array(locations)).compact.uniq
      slugs.empty? ? [ ALL_PREFECTURES_SLUG ] : slugs
    end

    # 都道府県（slug）単位で取得する。失敗した都道府県はログに残して飛ばし、他の結果は返す。
    # ただし全部が失敗したときは最後の例外を再 raise する（サイト全体がブロックされているときに
    # 「0 件」に見せると、ヒット無しと区別が付かないため）
    def fetch_each_prefecture(slugs)
      last_error = nil
      failed_count = 0
      fetched_events = slugs.flat_map do |slug|
        fetch_pages do |page_number|
          parse_list_page(http_get("#{BASE_URL}#{slug}?pageIndex=#{page_number}"))
        end
      rescue StandardError => e
        Rails.logger.warn("[Research] #{site_key} #{slug} の取得に失敗: #{e.class} #{e.message}")
        last_error = e
        failed_count += 1
        []
      end
      raise last_error if last_error && failed_count == slugs.size

      fetched_events
    end

    # 検索対象は name + description。description は結果の形（build_result）に無いので、パース時に searchableText として
    # 一時的に持たせ、フィルタ後に取り除く（フロントへは返さない）
    def matches_keyword?(event_result, keyword)
      searchable_text = normalize_for_match(event_result[:searchableText])
      keyword.to_s.split(/[[:space:]]+/).reject(&:empty?).all? { |word| searchable_text.include?(normalize_for_match(word)) }
    end

    # 全角/半角（「50代」と「５０代」）・大文字小文字は NFKC + downcase で同一視する
    def normalize_for_match(text)
      text.to_s.unicode_normalize(:nfkc).downcase
    end

    def parse_list_page(html)
      each_json_ld_event(parse_html(html)).filter_map { |event| build_event_result(event) }
    end

    def build_event_result(event)
      url = event["url"].to_s.strip
      return nil unless http_url?(url)

      title = event["name"].to_s.squish
      return nil if title.empty?

      place = event["location"].is_a?(Hash) ? event["location"] : {}
      image_url = Array(event["image"]).first
      start_date_text = jst_datetime_text(event["startDate"])

      build_result(
        title: title,
        url: url,
        starts_at: parse_iso8601_datetime(start_date_text),
        datetime_text: format_datetime_text(start_date_text),
        venue: place["name"].is_a?(String) ? place["name"] : nil,
        address: address_text(place["address"]),
        organizer: ORGANIZER_NAME,
        image_url: http_url?(image_url) ? image_url : nil
      ).merge(searchableText: "#{event['name']} #{event['description']}")
    end

    # address は文字列(住所そのまま)のことも PostalAddress の Hash のこともある。
    # Hash なら都道府県(addressRegion)、無ければ市区町村(addressLocality)
    def address_text(address)
      case address
      when String then address
      when Hash then address["addressRegion"].presence || address["addressLocality"]
      end
    end

    def jst_datetime_text(start_date)
      start_date.to_s.strip.then { |text| text.empty? ? nil : "#{text} #{JST_OFFSET}" }
    end
  end
end
