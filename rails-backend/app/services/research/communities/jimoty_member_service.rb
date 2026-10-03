module Research
  module Communities
    # ジモティー（jmty.jp）のメンバー募集（サークル・仲間募集）検索。
    # DOM は既存の Research::JimotyService（イベント）と同じで、カテゴリだけ /all/com になる。
    # サイト側に地域絞り込みを渡せないので、取得後に area で絞る。
    class JimotyMemberService < BaseService
      SITE_KEY = "jimoty_member".freeze
      SITE_LABEL = "ジモティー メンバー募集".freeze
      SEARCH_URL = "https://jmty.jp/all/com".freeze

      def search(keyword, locations = [])
        community_results = fetch_pages do |page_number|
          # ジモティーは最終ページを超えると 404 を返すので、404 は「もう無い」として扱う
          parse_search_page(http_get_allowing_not_found("#{SEARCH_URL}?keyword=#{CGI.escape(keyword)}&page=#{page_number}"))
        end
        filter_communities_by_location(community_results, locations)
      end

      private

      def parse_search_page(html)
        document = parse_html(html)

        document.css("li.p-articles-list-item").filter_map do |card_node|
          title_anchor = card_node.at_css(".p-item-title a")
          next unless title_anchor

          build_community_result(
            name: title_anchor.text,
            url: title_anchor["href"],
            area: card_node.at_css(".p-item-secondary-important")&.text&.squish,
            image_url: card_node.at_css("img.p-item-image")&.attr("src")
          )
        end
      end
    end
  end
end
