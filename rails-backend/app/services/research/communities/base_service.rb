module Research
  module Communities
    # コミュニティ（交流会・サロン・メンバー募集など「継続的な集まり」）検索サービスの基底クラス。
    # イベント検索の Research::BaseService を継承し、HTTP・ページング・地域エイリアスの仕組みを再利用する。
    #
    # ■ イベント用と分けている理由
    #   イベントは「開催日・会場」を持つが、コミュニティは「名前・活動エリア・月額・メンバー数」が中心で、
    #   返すキーが違う（build_result とは別に build_community_result を使う）。
    #   地域の後段フィルタも、イベント用の title/venue/address ではなく name/area/description を見る必要がある。
    #
    # ■ サブクラスを書くときの約束
    #   - SITE_KEY / SITE_LABEL を定義し、search(keyword, locations) を実装する
    #   - 返す Hash は必ず build_community_result 経由で作る
    #   - 引数なしで new できること（コントローラが service_class.new.search(...) で呼ぶ）
    class BaseService < Research::BaseService
      private

      def build_community_result(name:, url:, description: nil, area: nil, fee: nil, member_count: nil,
                                 image_url: nil, organizer: nil)
        {
          site: site_key,
          siteLabel: site_label,
          name: name.to_s.strip,
          url: url,
          description: description.to_s.strip.presence,
          area: area.to_s.strip.presence,
          fee: fee.to_s.strip.presence,
          memberCount: member_count,
          imageUrl: image_url.to_s.strip.presence,
          organizer: organizer.to_s.strip.presence
        }
      end

      # サイト側に地域絞り込みがないサービス向けの後段フィルタ。
      # 名前・活動エリア・説明のいずれかに、選択された場所のエイリアスが含まれれば残す。
      def filter_communities_by_location(community_results, locations)
        return community_results if locations.blank?

        match_terms = locations.flat_map { |location| LOCATION_ALIASES[location] || [ location ] }
        community_results.select do |community_result|
          searchable_text = [ community_result[:name], community_result[:area], community_result[:description] ].compact.join(" ")
          match_terms.any? { |term| searchable_text.include?(term) }
        end
      end
    end
  end
end
