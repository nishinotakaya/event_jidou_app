module Research
  # こくちーずプロ（kokuchpro.com）のイベント検索。
  # 経営者交流会・異業種交流会の掲載数が国内で最も多く、このリサーチの主力サイト。
  # 検索結果はサーバーレンダリングされた HTML（a.event_name がカードのタイトルリンク）。
  class KokuchproService < BaseService
    SITE_KEY = "kokuchpro".freeze
    SITE_LABEL = "こくちーずプロ".freeze
    SEARCH_URL = "https://www.kokuchpro.com/s/".freeze

    # 地域別検索パス /s/area-<地域名>/ の地域名（サイト側で絞り込める）
    AREA_NAMES = {
      "online" => "オンライン", "東京" => "東京都", "神奈川" => "神奈川県", "千葉" => "千葉県",
      "埼玉" => "埼玉県", "大阪" => "大阪府", "京都" => "京都府", "兵庫" => "兵庫県",
      "愛知" => "愛知県", "福岡" => "福岡県", "北海道" => "北海道", "沖縄" => "沖縄県"
    }.freeze

    def search(keyword, locations = [])
      area_names = locations.filter_map { |location| AREA_NAMES[location] }
      search_urls =
        if area_names.empty?
          [ "#{SEARCH_URL}?q=#{CGI.escape(keyword)}#{date_query}" ]
        else
          area_names.map { |area_name| "#{SEARCH_URL}area-#{CGI.escape(area_name)}/?q=#{CGI.escape(keyword)}#{date_query}" }
        end

      results = search_urls.flat_map do |search_url|
        # こくちーずは検索ヒット0件のときも 404 を返すので、404 は空ページ扱いにする
        fetch_pages { |page_number| parse_search_page(http_get_allowing_not_found(page_url(search_url, page_number))) }
      end
      results.uniq { |result| result[:url] }
    end

    # 1ページ目は素の検索URL、2ページ目以降は ?page=N を足す（既に ?q= が付いている前提）。
    # ページャのリンクは /search/index/q-<keyword>/p-2/?page=N という別形式で出ているが、
    # そちらを叩くとカードのマークアップが違って 0 件になる。/s/?q=…&page=N を使うこと。
    def page_url(search_url, page_number)
      page_number == 1 ? search_url : "#{search_url}&page=#{page_number}"
    end

    private

    # 検索フォームと同じ start_date / end_date。開催日で絞ると取得ページ数（3ページ）を
    # 希望の期間に使い切れるので、後段フィルタ任せにせずサイト側でも絞る。
    # 区切りはハイフン固定（2026/10/01 のようなスラッシュ区切りは 404 になる。2026-08-22 実測）。
    def date_query
      query = "&start_date=#{date_range.from_param}"
      query += "&end_date=#{date_range.to_param}" if date_range.to_param
      query
    end

    def parse_search_page(html)
      document = parse_html(html)

      document.css("a.event_name").filter_map do |title_anchor|
        event_url = title_anchor["href"]
        next if event_url.blank?

        card_node = title_anchor.ancestors.find { |node| node.css(".fui-calendar").any? }
        datetime_text = card_node&.css(".fui-calendar")&.first&.parent&.text&.strip
        venue_text = card_node&.css(".fui-location")&.first&.parent&.text&.strip

        build_result(
          title: title_anchor.text,
          url: event_url,
          starts_at: parse_japanese_datetime(datetime_text),
          datetime_text: datetime_text,
          venue: venue_text,
        )
      end
    end
  end
end
