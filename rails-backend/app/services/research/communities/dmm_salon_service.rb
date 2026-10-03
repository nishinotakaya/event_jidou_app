module Research
  module Communities
    # DMMオンラインサロン（lounge.dmm.com）の検索。
    # ページ送りは `&page=n` ではなくパス形式（/search/page/<n>/）でないとサイト側で効かない。
    # `keyword=` はサイト側で無視されて全件の新着一覧が返る。検索フォームの input 名は searchstr（2026-10-03 実測）。
    # 結果が1ページだけのキーワードでは2ページ目が 404 になるため、404 は「もう無い」として扱う。
    # サロンはすべてオンラインなので地域指定は無視する。
    class DmmSalonService < BaseService
      SITE_KEY = "dmm_salon".freeze
      SITE_LABEL = "DMMオンラインサロン".freeze
      BASE_URL = "https://lounge.dmm.com".freeze
      IMAGE_BASE_URL = "https://prd-lounge.imgix.net".freeze
      ONLINE_AREA = "オンライン".freeze

      def search(keyword, _locations = [])
        fetch_pages do |page_number|
          parse_search_page(http_get_allowing_not_found(search_url(keyword, page_number)))
        end
      end

      private

      def search_url(keyword, page_number)
        encoded_keyword = CGI.escape(keyword)
        return "#{BASE_URL}/search/?searchstr=#{encoded_keyword}" if page_number == 1

        "#{BASE_URL}/search/page/#{page_number}/?searchstr=#{encoded_keyword}"
      end

      def parse_search_page(html)
        document = parse_html(html)

        document.css("li.c-salonCard").filter_map do |card_node|
          # カード内の入れ子の a は「入会ページへ」ボタンなので、直下の a だけを詳細リンクとみなす
          detail_anchor = card_node.at_xpath("./a[@href]")
          name = card_node.at_css(".c-salonCard__detail__title")&.text
          next if detail_anchor.nil? || name.blank?

          image_path = card_node.at_css("img[ix-path]")&.attr("ix-path")
          build_community_result(
            name: name,
            url: URI.join(BASE_URL, detail_anchor["href"]).to_s,
            description: card_node.at_css(".c-salonCard__detail__description")&.text&.squish,
            area: ONLINE_AREA,
            fee: card_node.at_css(".c-salonCard__detail__place")&.text&.squish,
            image_url: image_path.present? ? "#{IMAGE_BASE_URL}/#{image_path}" : nil
          )
        end
      end
    end
  end
end
