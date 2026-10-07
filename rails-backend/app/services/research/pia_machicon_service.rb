module Research
  # ピア街コン（pia-machicon.piary.jp、ピアリー運営のポータル）の街コン・婚活パーティー検索。
  #
  # - JSON-LD には検索結果が入っていない（おすすめ枠の3件だけ）ので、HTML のカードを読む
  # - 1ページ18件。結果を超えた pageno は 404 ではなく 0件の 200 が返るので fetch_pages がそこで止まる
  #   （2026-10-07 実測。「スポーツ」3件・「婚活」173件）
  # - 検索結果は .searchResult__list の中の section.recommendEvent__cont だけ。
  #   同じ section.recommendEvent__cont クラスがページ下部の「オススメの街コン」枠にも使われており、
  #   そこは検索条件と無関係なので、必ず .searchResult__list 配下にスコープする（外すと毎回同じ数件が混ざる）
  # - 日時は「10月12日(月) 16:00〜」のように年が無い。parse_japanese_datetime が「今日以降で最も近い年」に寄せる
  # - 会場名は一覧に出ない。都道府県だけ address に入れる
  # - 地域は検索条件に併用できないため filter_by_location で後段フィルタする（address の都道府県に掛かる）
  class PiaMachiconService < BaseService
    SITE_KEY = "pia_machicon".freeze
    SITE_LABEL = "ピア街コン".freeze
    SEARCH_URL = "https://pia-machicon.piary.jp/products/list".freeze
    RESULT_CARD_SELECTOR = ".searchResult__list section.recommendEvent__cont".freeze

    def search(keyword, locations = [])
      fetched_events = fetch_pages do |page_number|
        parse_search_page(http_get("#{SEARCH_URL}?keyword=#{CGI.escape(keyword)}&pageno=#{page_number}"))
      end
      filter_by_location(fetched_events, locations)
    end

    private

    def parse_search_page(html)
      parse_html(html).css(RESULT_CARD_SELECTOR).filter_map { |card_node| build_event_result(card_node) }
    end

    def build_event_result(card_node)
      url = absolute_url(card_node.at_css("a.recommendEvent__cont--link")&.[]("href"))
      return nil unless url

      date_node = card_node.at_css("p.recommendEvent__cont--date")
      prefecture_node = date_node&.at_css("span.recommendEvent__cont--date--pref")
      datetime_text = extract_datetime_text(date_node)

      build_result(
        title: card_node.at_css("h3.title-fav__wrap--title")&.text.to_s.strip,
        url: url,
        starts_at: parse_japanese_datetime(datetime_text),
        datetime_text: datetime_text,
        address: prefecture_node&.text.to_s.strip,
        image_url: absolute_image_url(card_node)
      )
    end

    # 都道府県の span を取り除いた残り（「10月12日(月) 16:00〜」）が日時表記
    def extract_datetime_text(date_node)
      return nil unless date_node

      date_clone = date_node.dup
      date_clone.css("span.recommendEvent__cont--date--pref").each(&:remove)
      date_clone.text.squish
    end

    def absolute_image_url(card_node)
      absolute_url(card_node.at_css("img.recommendEvent__cont--mainImg")&.[]("src"))
    end

    # 外部 HTML 由来の 1 件の不正な値（空白入りで結合できない href など）でサイト全体の検索を落とさないよう、
    # 結合できなければ nil にする。javascript: 等を <a href> に流さないよう http(s) 以外も nil。
    # 呼び出し側は url が nil ならカードごと捨て、画像が nil なら画像だけ空にする
    def absolute_url(path_or_url)
      # 空文字を URI.join に渡すと SEARCH_URL 自身になってしまうので、先に落とす
      return nil if path_or_url.to_s.strip.empty?

      # escape の既定は % も変換して %E3 → %25E3 に壊すため、対象を非 ASCII・空白・制御文字だけに限定する
      escaped_url = URI::DEFAULT_PARSER.escape(path_or_url.to_s.strip, /[^\x21-\x7E]/)
      joined_url = URI.join(SEARCH_URL, escaped_url).to_s
      http_url?(joined_url) ? joined_url : nil
    rescue URI::InvalidURIError
      nil
    end
  end
end
