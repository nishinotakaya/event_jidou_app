module Research
  module Communities
    # CAMPFIREコミュニティ（community.camp-fire.jp）の検索。
    # コミュニティはすべてオンライン運営で、一覧に会費の表示が無いため、地域指定は無視し fee は nil にする。
    class CampfireService < BaseService
      SITE_KEY = "campfire".freeze
      SITE_LABEL = "CAMPFIREコミュニティ".freeze
      BASE_URL = "https://community.camp-fire.jp".freeze
      ONLINE_AREA = "オンライン".freeze

      def search(keyword, _locations = [])
        fetch_pages do |page_number|
          parse_search_page(http_get("#{BASE_URL}/projects/search?word=#{CGI.escape(keyword)}&page=#{page_number}"))
        end
      end

      private

      def parse_search_page(html)
        document = parse_html(html)

        document.css(".fc-card").filter_map do |card_node|
          card_anchor = card_node.at_css("a.fc-card-anchor[href]")
          name = card_node.at_css(".fc-card__inner__body__title")&.text
          next if card_anchor.nil? || name.blank?

          build_community_result(
            name: name,
            url: URI.join(BASE_URL, card_anchor["href"]).to_s,
            area: ONLINE_AREA,
            # 主宰者のプロフィール画像（profile--image 内の img）ではなく、サムネイル側を使う
            image_url: card_node.at_css(".fc-card__inner__thumbnail img[data-src]")&.attr("data-src"),
            organizer: card_node.at_css(".fc-card__inner__body__profile--name")&.text&.squish
          )
        end
      end
    end
  end
end
