require "net/http"
require "uri"
require "time"
require "json"
require "nokogiri"

module Research
  # 各イベントサイトの横断検索サービスの基底クラス。
  # サブクラスは search(keyword) を実装し、build_result で正規化した Hash の配列を返す。
  class BaseService
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36".freeze
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 20
    MAX_REDIRECTS = 3
    JST_OFFSET = "+09:00".freeze
    # JSON-LD の文字列リテラル内に生のまま現れる制御文字の置き換え表
    CONTROL_CHARACTER_ESCAPES = { "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }.freeze

    # 場所キー（"online" または都道府県の短縮名）→ テキストマッチ用のエイリアス。
    # 会場/住所に都道府県名が入らないサイト向けに、主要な市区・駅名も含める。
    LOCATION_ALIASES = {
      "online" => %w[オンライン online Online ONLINE Zoom zoom ウェビナー リモート Web開催 web開催],
      "東京" => %w[東京 新宿 渋谷 銀座 池袋 品川 秋葉原 六本木 恵比寿 新橋 神田 上野 日本橋 丸の内 浜松町 五反田 中野 吉祥寺 立川 町田 八王子 有楽町 赤坂 虎ノ門],
      "神奈川" => %w[神奈川 横浜 川崎 藤沢 鎌倉 相模原 武蔵小杉],
      "千葉" => %w[千葉 船橋 柏 松戸 津田沼 幕張 市川 浦安],
      "埼玉" => %w[埼玉 大宮 浦和 川口 所沢 越谷],
      "大阪" => %w[大阪 梅田 難波 なんば 心斎橋 淀屋橋 本町 天王寺 新大阪],
      "京都" => %w[京都 烏丸 河原町],
      "兵庫" => %w[兵庫 神戸 三宮 姫路 西宮],
      "愛知" => %w[愛知 名古屋 栄 金山],
      "福岡" => %w[福岡 博多 天神 小倉],
      "北海道" => %w[北海道 札幌],
      "沖縄" => %w[沖縄 那覇]
    }.freeze

    # 1サイト・1条件あたりに辿る検索結果ページ数の上限
    MAX_SEARCH_PAGES = 3

    def search(_keyword, _locations = [])
      raise NotImplementedError, "#{self.class.name}#search is not implemented"
    end

    private

    # ページ番号を渡すブロックを繰り返し呼び、URL重複を除いて結合する。
    # 新規ヒットが無くなった時点（＝最終ページ）で打ち切る。
    def fetch_pages(max_pages: MAX_SEARCH_PAGES)
      collected_results = []
      seen_urls = {}

      (1..max_pages).each do |page_number|
        fresh_results = yield(page_number).reject { |result| seen_urls[result[:url]] }
        break if fresh_results.empty?

        fresh_results.each { |result| seen_urls[result[:url]] = true }
        collected_results.concat(fresh_results)
      end
      collected_results
    end

    def site_key
      self.class::SITE_KEY
    end

    def site_label
      self.class::SITE_LABEL
    end

    def http_get(url, headers = {})
      redirects = 0
      loop do
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = USER_AGENT
        request["Accept-Language"] = "ja,en;q=0.8"
        headers.each { |name, value| request[name] = value }

        response = http.request(request)
        case response
        when Net::HTTPRedirection
          redirects += 1
          raise "リダイレクトが多すぎます（#{url}）" if redirects > MAX_REDIRECTS
          url = URI.join(url, response["Location"]).to_s
        when Net::HTTPSuccess
          body = response.body.to_s.force_encoding(Encoding::UTF_8)
          # Peatix / TechPlay 等はデータセンターIP（Heroku）に対し 200/202 + 空ボディを返してブロックする
          raise "サイト側にアクセスをブロックされました（サーバーIP制限の可能性）" if body.strip.empty?

          return body
        else
          raise "HTTP #{response.code}（#{uri.host}）"
        end
      end
    end

    def parse_html(html)
      Nokogiri::HTML(html)
    end

    # サイト側に地域絞り込みがないサービス向けの後段フィルタ。
    # タイトル・会場・住所・日時テキストのいずれかに、選択された場所のエイリアスが含まれれば残す。
    def filter_by_location(results, locations)
      return results if locations.blank?

      match_terms = locations.flat_map { |location| LOCATION_ALIASES[location] || [ location ] }
      results.select do |result|
        searchable_text = [ result[:title], result[:venue], result[:address], result[:datetimeText] ].compact.join(" ")
        match_terms.any? { |term| searchable_text.include?(term) }
      end
    end

    # ページ内の JSON-LD から schema.org Event だけを取り出す。
    # 壊れたブロック（レビュー用の JSON など）は黙って読み飛ばす。
    def each_json_ld_event(document)
      document.css('script[type="application/ld+json"]').flat_map do |script_node|
        extract_json_ld_events(JSON.parse(sanitize_json_ld(script_node.text)))
      rescue JSON::ParserError
        []
      end
    end

    # Event が直接並ぶ書き方と、ItemList の itemListElement[].item に入る書き方の両方に対応する。
    def extract_json_ld_events(node)
      case node
      when Array
        node.flat_map { |child_node| extract_json_ld_events(child_node) }
      when Hash
        return [ node ] if node["@type"].to_s == "Event"

        extract_json_ld_events(node["itemListElement"] || node["item"] || [])
      else
        []
      end
    end

    # JSON-LD は手書きテンプレートで生成しているサイトが多く、そのままでは JSON.parse できないことがある。
    #   - `"有楽町""` のように閉じ引用符が重複する（doomo）
    #   - 説明文に生の改行が入る（e-venz）
    # 重複引用符の補正は、空文字 `""` を巻き込まないよう「中身のある文字列の直後」に限定する。
    DUPLICATED_CLOSING_QUOTE = /([^"\s:,{\[])""(\s*[,}\]])/

    def sanitize_json_ld(text)
      escape_control_characters_in_strings(text.gsub(DUPLICATED_CLOSING_QUOTE, '\1"\2'))
    end

    def escape_control_characters_in_strings(text)
      sanitized = +""
      in_string = false
      escaped = false

      text.each_char do |character|
        if in_string && escaped
          sanitized << character
          escaped = false
          next
        end

        case character
        when "\\"
          escaped = in_string
          sanitized << character
        when '"'
          in_string = !in_string
          sanitized << character
        else
          sanitized << (in_string ? CONTROL_CHARACTER_ESCAPES.fetch(character, character) : character)
        end
      end
      sanitized
    end

    # "2026-08-12T14:15:00+09:00" 形式。
    # オフセットが "+9:00" と1桁だったり秒が省略されたりするサイトがあるため、補正＋Time.parse で拾う。
    def parse_iso8601_datetime(text)
      return nil if text.blank?

      normalized = text.strip.sub(/([+-])(\d):/, '\1' + "0" + '\2:')
      Time.iso8601(normalized)
    rescue ArgumentError
      begin
        Time.parse(normalized)
      rescue ArgumentError
        nil
      end
    end

    def format_datetime_text(text)
      parse_iso8601_datetime(text)&.getlocal(JST_OFFSET)&.strftime("%Y年%-m月%-d日 %H:%M")
    end

    # 「2026年8月20日(木) 16:00〜17:00」のような日本語日時文字列を Time に変換する。
    # 時刻が取れない場合は 00:00、日付が取れない場合は nil。
    def parse_japanese_datetime(text)
      return nil if text.blank?

      date_match = text.match(/(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日/)
      return nil unless date_match

      time_match = text.match(/(\d{1,2}):(\d{2})/)
      hour = time_match ? time_match[1].to_i : 0
      minute = time_match ? time_match[2].to_i : 0
      Time.new(date_match[1].to_i, date_match[2].to_i, date_match[3].to_i, hour, minute, 0, JST_OFFSET)
    rescue ArgumentError
      nil
    end

    def build_result(title:, url:, starts_at: nil, datetime_text: nil, venue: nil, address: nil,
                     organizer: nil, participants: nil, capacity: nil, image_url: nil)
      {
        site: site_key,
        siteLabel: site_label,
        title: title.to_s.strip,
        url: url,
        startsAt: starts_at&.iso8601,
        datetimeText: datetime_text.presence,
        venue: venue.presence,
        address: address.presence,
        organizer: organizer.presence,
        participants: participants,
        capacity: capacity,
        imageUrl: image_url.presence
      }
    end
  end
end
