module Research
  module Communities
    # 商工会議所青年部（YEG・417 単会）の名簿。一覧 1 ページ（/about/chambers）を 1 回だけ取得する。
    # 都道府県ごとに `h4#<slug>` があり、その下に table が複数（wp-block-column ごと）並ぶ。
    # 行は「td 会議所名 / td リンク（公式・Facebook…）」で、url は最初のリンク（公式サイト）を使う。
    # h4 直後にある Facebook だけの <p>（都道府県単位のリンク）は table の外なので会議所として拾わない。
    # リンクが 1 つも無い会議所は、一覧の該当都道府県の位置（アンカー）を url にする。
    class YegService < BaseService
      SITE_KEY = "yeg".freeze
      SITE_LABEL = "商工会議所青年部".freeze
      LIST_URL = "https://www.yeg.jp/about/chambers".freeze

      def search(keyword, locations = [])
        filter_roster_by_keyword_or_location(parse_list_page(http_get(LIST_URL)), keyword, locations)
      end

      private

      def parse_list_page(html)
        parse_html(html).css("table tr").filter_map do |row_node|
          name_cell, link_cell = row_node.css("td")
          prefecture_heading = row_node.at_xpath("preceding::h4[@id][1]")
          next if name_cell.nil? || name_cell.text.squish.empty? || prefecture_heading.nil?

          build_community_result(
            name: name_cell.text.squish,
            url: chamber_url(link_cell, prefecture_heading["id"]),
            area: prefecture_heading.text.squish
          )
        end
      end

      def chamber_url(link_cell, prefecture_slug)
        first_href = link_cell&.at_css("a[href]")&.attr("href")
        return "#{LIST_URL}##{prefecture_slug}" if first_href.blank?

        URI.join(LIST_URL, first_href).to_s
      end
    end
  end
end
