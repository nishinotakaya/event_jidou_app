module Research
  # つなげーと（tunagate.com）の社会人サークル・趣味友イベント検索。投稿先としても使っているサイト。
  #
  # - 入口は /search/all。/search はキーワードを無視して全件一覧を返す（2026-09-12 実測）
  # - 1ページ72件。2ページ目以降の URL は React props（PAGINATION_COMPONENT）の baseUrl + extraParams で組む
  # - keyword と page を並べただけの URL は1ページ目を返すだけなので、props 無しには辿れない（同日実測）
  # - ページ超過は 404 ではなくカード0件の 200（同日 page=99）。http_get_allowing_not_found は要らない
  class TunagateService < BaseService
    SITE_KEY = "tunagate".freeze
    SITE_LABEL = "つなげーと".freeze
    BASE_URL = "https://tunagate.com".freeze
    SEARCH_PATH = "/search/all".freeze

    # ページ送り情報を持つ React コンポーネント（検索フォームのカレンダー）
    PAGINATION_COMPONENT = "search/search_form_calendar_erb".freeze

    # 2ページ目以降の URL の組み立て方。サイト側の実装（baseUrl + extraParams）に合わせる。
    Pagination = Struct.new(:base_url, :extra_params) do
      def page_url(page_number)
        "#{BASE_URL}#{base_url}?page=#{page_number}#{extra_params}"
      end
    end

    def search(keyword, locations = [])
      first_page_html = http_get(search_url(keyword))
      pagination = parse_pagination(first_page_html)

      results = fetch_pages do |page_number|
        next parse_search_page(first_page_html) if page_number == 1
        # ページ送りを見失っても、取れている1ページ目は捨てない（0件のページとして打ち切らせる）
        next [] if pagination.nil?

        parse_search_page(http_get(pagination.page_url(page_number)))
      end
      filter_by_location(results, locations)
    end

    private

    def search_url(keyword)
      "#{BASE_URL}#{SEARCH_PATH}?keyword=#{CGI.escape(keyword)}"
    end

    # ページ構造が変わって props を読めなくなったら nil を返し、1ページ目だけで続行する
    def parse_pagination(html)
      props = parse_html(html).at_css("[data-react-class='#{PAGINATION_COMPONENT}']")&.attr("data-react-props")
      if props.blank?
        Rails.logger.warn("[Research] つなげーとのページ送り情報が読めません（1ページ目のみ取得します）")
        return nil
      end

      parsed = JSON.parse(props)
      Pagination.new(parsed["baseUrl"].presence || SEARCH_PATH, parsed["extraParams"].to_s)
    end

    def parse_search_page(html)
      parse_html(html).css("a.event-grid-link").filter_map { |card_node| build_card_result(card_node) }
    end

    def build_card_result(card_node)
      path = card_node["href"].to_s
      return nil if path.empty?

      # 「9/13(日) 13:00」形式。年が無いので parse_japanese_datetime が直近の年に寄せる
      datetime_text = text_of(card_node, ".event-grid-date")

      build_result(
        title: text_of(card_node, ".event-grid-title"),
        url: "#{BASE_URL}#{path}",
        starts_at: parse_japanese_datetime(datetime_text),
        datetime_text: datetime_text,
        venue: text_of(card_node, ".event-grid-pref"),
        organizer: text_of(card_node, ".event-grid-circle-name"),
        # 一覧画像は遅延読み込みなので src ではなく data-src に入っている
        image_url: card_node.at_css("img.event-grid-image")&.attr("data-src"),
      )
    end

    def text_of(card_node, selector)
      card_node.at_css(selector)&.text&.squish
    end
  end
end
