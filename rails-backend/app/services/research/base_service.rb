require "net/http"
require "uri"
require "time"
require "json"
require "nokogiri"

module Research
  # 各イベントサイトの横断検索サービスの基底クラス。
  # サブクラスは search(keyword, locations) を実装し、build_result で正規化した Hash の配列を返す。
  #
  # ■ ここに共通処理を置いている理由
  #   イベントサイトは HTML も API もバラバラだが、ハマりどころは驚くほど共通している。
  #   個々のサービスに同じ回避策を書き散らさないよう、下記4つはこのクラスが引き受ける。
  #
  #   1. データセンターIPブロック … Heroku から叩くと 200/202 なのに本文が空で返るサイトがある（http_get）
  #   2. 壊れた JSON-LD        … 手書きテンプレ由来で JSON.parse に失敗する（sanitize_json_ld）
  #   3. 日時表記のゆれ         … ISO8601 もどき・日本語表記が混在する（parse_iso8601_datetime / parse_japanese_datetime）
  #   4. 地域絞り込みの有無      … サイト側で絞れない場合の後段フィルタ（filter_by_location）
  #
  # ■ サブクラスを書くときの約束
  #   - 返す Hash は必ず build_result 経由で作る（フロントは site/title/url/startsAt … のキーに依存している）
  #   - 複数ページを辿るときは fetch_pages を使う（重複除去と打ち切り条件が入っている）
  #   - 例外はそのまま投げてよい。ResearchController がサイト単位で捕まえて errors に入れる
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

    # 1サイト・1条件あたりに辿る検索結果ページ数の上限。
    # 3 にしている根拠（2026-08-15 実測 / キーワード「経営者 交流会」）:
    #   - 1ページだけだと取りこぼしが大きい（Peatix はヒット 752 件に対し 1ページ 20 件しか取れていなかった）
    #   - 3ページなら kokuchpro 120件 / Peatix 150件 / ジモティー 150件 まで伸びて、1サイト 1〜3 秒に収まる
    #   - これ以上増やすと検索の体感が落ち、後ろのページほど関連度も落ちる
    MAX_SEARCH_PAGES = 3

    # 検索条件のうち「開催日」の部分。サイト側の日付パラメータを組み立てるためにサブクラスが参照する。
    # 取得後の絞り込み（終了イベントの除外）は ResearchController が DateRange#filter でまとめて行う。
    attr_reader :date_range

    def initialize(date_range = DateRange.new)
      @date_range = date_range
    end

    def search(_keyword, _locations = [])
      raise NotImplementedError, "#{self.class.name}#search is not implemented"
    end

    private

    # ページ番号を渡すブロックを繰り返し呼び、URL重複を除いて結合する。
    #
    # 「新規ヒットが1件も無かったら打ち切る」のは、最終ページを超えても 200 で同じ内容を返し続ける
    # サイトがあるため（Doorkeeper は 2ページ目以降がほぼ同じ内容）。件数ではなく URL の新規性で判定する。
    # なお e-venz のようにページ内で同じイベントが重複して現れるサイトもあるので、
    # 呼び出し側は最終的に uniq をかけること。
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
          # データセンターIP（Heroku）からのアクセスを、エラーではなく「空ボディの成功レスポンス」で
          # 弾いてくるサイトがある。素通しすると「0件ヒット」と区別が付かず原因調査で必ず迷うので、
          # ここで明示的に落とす。Heroku dyno 実測（2026-08-15）:
          #   Peatix   200 / 0 バイト   （同じリクエストがローカル回線からは正常に JSON を返す）
          #   TechPlay 202 / 0 バイト
          #   こくちーずプロ 200 / 371KB（＝ブロックされていない）
          # Peatix は検索APIが CORS 許可済みなので、ブラウザから取り直す逃げ道を用意してある。
          # 詳細は Research::PeatixService と Api::ResearchController#normalize を参照。
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

    # 「ヒット0件」や「これ以上ページが無い」を 404 で返してくるサイト（ジモティー・こくちーずプロ）向け。
    # そのまま例外にすると、キーワード次第でサイトごと検索失敗扱いになってしまう
    # （実例: ジモティーは "AI プログラミングスクール" の2ページ目が 404 で、1ページ目の結果まで捨てていた）。
    # 空文字を返せば「0件のページ」として扱われ、fetch_pages がそこで打ち切ってくれる。
    def http_get_allowing_not_found(url, headers = {})
      http_get(url, headers)
    rescue RuntimeError => e
      raise unless e.message.include?("HTTP 404")

      ""
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
    # 1ページに複数の <script type="application/ld+json"> があり、Event 以外（Organization / Review /
    # BreadcrumbList）も混ざる。補正しても読めないブロックは、そのページ全体を諦めるのではなく
    # そのブロックだけ捨てる（Review の JSON が壊れていてイベントが 1 件も取れない、を避けるため）。
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

    # JSON-LD は手書きテンプレートで生成しているサイトが多く、そのままでは JSON.parse に失敗する。
    # 実際に踏んだ壊れ方は2種類:
    #   - 閉じ引用符の重複    `"area" : "有楽町""`      （doomo。値の直後にもう1つ " が入る）
    #   - 文字列内の生の改行  `"description" : "…改行…"` （e-venz。JSON では \n にエスケープが必要）
    #
    # 重複引用符の補正で「中身のある文字列の直後」に限定しているのは、素朴に /""/ を潰すと
    # 正常な空文字 `"name" : "",` まで `"name" : ",` に壊してしまい、
    # そこから先が全部パース不能になるため（実際にこれで e-venz のエリアページが 0 件になった）。
    DUPLICATED_CLOSING_QUOTE = /([^"\s:,{\[])""(\s*[,}\]])/

    def sanitize_json_ld(text)
      escape_control_characters_in_strings(text.gsub(DUPLICATED_CLOSING_QUOTE, '\1"\2'))
    end

    # 文字列リテラルの内側にある制御文字だけをエスケープする。
    # 単純な gsub だと JSON の整形用の改行まで潰してしまうので、
    # 「いま文字列の中か」「直前がバックスラッシュか」を持ちながら1文字ずつ舐める。
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

    # JSON-LD の startDate（"2026-08-12T14:15:00+09:00" 形式）を Time にする。
    # Time.iso8601 は厳密で、下記のどちらでも ArgumentError になるため2段構えにしている:
    #   - オフセットが1桁  "2026-08-12T14:00+9:00"     （doomo）
    #   - 秒が省略される    "2026-08-12T14:00+09:00"    （doomo。iso8601 は秒必須）
    # 1桁オフセットだけは Time.parse も解釈を誤るので、先に正規化してから渡す。
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

    # 「2026年8月20日(木) 16:00〜17:00」「8月28日 21:00 - 8月29日 2:00」「開催日:8/26」のような
    # 日本語の日時表記を Time に変換する。時刻が取れない場合は 00:00、日付が取れない場合は nil。
    #
    # 年を省略するサイトがある（Doorkeeper「8月28日 21:00」/ ジモティー「開催日:8/26」）。
    # 年が無いものを nil にしていると開催日で絞れず、終了イベントの除外からも漏れてしまうので、
    # 省略時は「今日以降で最も近い年」とみなす（8月に見る 12月19日 は今年、8月に見る 1月5日 は来年）。
    def parse_japanese_datetime(text)
      date = parse_japanese_date(text)
      return nil unless date

      time_match = text.match(/(\d{1,2}):(\d{2})/)
      hour = time_match ? time_match[1].to_i : 0
      minute = time_match ? time_match[2].to_i : 0
      Time.new(date.year, date.month, date.day, hour, minute, 0, JST_OFFSET)
    rescue ArgumentError
      nil
    end

    JAPANESE_DATE = /(?:(\d{4})年\s*)?(\d{1,2})月\s*(\d{1,2})日/
    SLASH_DATE = %r{(\d{1,2})/(\d{1,2})}

    def parse_japanese_date(text)
      return nil if text.blank?

      match = text.match(JAPANESE_DATE) || text.match(SLASH_DATE)
      return nil unless match

      # SLASH_DATE は年を持たない（捕獲は月・日の2つ）ので、年の位置に nil を補って揃える
      year, month, day = match.captures.size == 3 ? match.captures : [ nil, *match.captures ]
      build_date(year, month, day)
    end

    # 年が指定されていなければ「今日以降で最も近い年」に寄せる。
    def build_date(year, month, day)
      return Date.new(year.to_i, month.to_i, day.to_i) if year

      today = Time.now.getlocal(JST_OFFSET).to_date
      date = Date.new(today.year, month.to_i, day.to_i)
      date < today ? date.next_year : date
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
