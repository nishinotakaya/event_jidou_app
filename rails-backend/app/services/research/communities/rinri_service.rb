module Research
  module Communities
    # 倫理法人会（47 都道府県）の名簿。一覧 1 ページ（/houjin/list/）に全団体が載っているので 1 回だけ取得し、
    # キーワード（団体名）と地域（住所）は filter_roster_by_keyword_or_location で後段絞り込みする。
    # 各団体は div.houjin で、中身は「〒… <br>住所 <br>TEL/<span>番号</span> FAX/…」と混ざっているため、
    # TEL より前を住所（area）、TEL 以降を連絡先（description）に分ける。
    class RinriService < BaseService
      SITE_KEY = "rinri".freeze
      SITE_LABEL = "倫理法人会".freeze
      LIST_URL = "https://www.rinri-jpn.or.jp/houjin/list/".freeze
      POSTAL_CODE_PATTERN = /〒\s*\d{3}-?\d{4}/

      def search(keyword, locations = [])
        filter_roster_by_keyword_or_location(parse_list_page(http_get(LIST_URL)), keyword, locations)
      end

      private

      def parse_list_page(html)
        parse_html(html).css("div.houjin").filter_map do |houjin_node|
          name_anchor = houjin_node.at_css("h4 a[href]")
          name = name_anchor&.text
          next if name.blank?

          address_text, contact_text = split_address_and_contact(houjin_node.at_css("div")&.text.to_s)
          build_community_result(
            name: name,
            url: URI.join(LIST_URL, name_anchor["href"]).to_s,
            description: contact_text,
            area: address_text.sub(POSTAL_CODE_PATTERN, "").squish
          )
        end
      end

      def split_address_and_contact(detail_text)
        contact_start = detail_text.index("TEL")
        return [ detail_text.squish, nil ] if contact_start.nil?

        [ detail_text[0...contact_start].squish, detail_text[contact_start..].squish ]
      end
    end
  end
end
