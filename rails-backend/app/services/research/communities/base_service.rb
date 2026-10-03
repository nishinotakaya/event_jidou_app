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

      # url が http/https 以外（javascript: 等・パース不能を含む）なら nil を返す。呼び出し側は filter_map / compact で除外する。
      # image_url が http/https 以外なら、結果は残して画像だけ nil にする。
      def build_community_result(name:, url:, description: nil, area: nil, fee: nil, member_count: nil,
                                 image_url: nil, organizer: nil)
        return nil unless http_url?(url)

        safe_image_url = http_url?(image_url) ? image_url.to_s.strip : nil
        {
          site: site_key,
          siteLabel: site_label,
          name: name.to_s.strip,
          url: url,
          description: description.to_s.strip.presence,
          area: area.to_s.strip.presence,
          fee: fee.to_s.strip.presence,
          memberCount: member_count,
          imageUrl: safe_image_url,
          organizer: organizer.to_s.strip.presence
        }
      end

      # 日本語を含む URL（Meetup のグループ名 URL など）は実在するので、非 ASCII を % エンコードしてから判定する
      def http_url?(value)
        URI.parse(URI::DEFAULT_PARSER.escape(value.to_s.strip)).is_a?(URI::HTTP)
      rescue URI::InvalidURIError
        false
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

      # 一覧 1 ページを丸ごと取る団体名簿（倫理法人会・商工会議所青年部）向けの絞り込み。
      # 名簿はサイト側に検索が無いので、こちらで次の規則を適用する。
      #   - 地域を選んだ場合: その地域の団体は、キーワードに一致しなくても残す
      #     （「経営者」「交流会」のような一般語で 0 件になるのを避けるため）
      #   - キーワードが団体名に一致する団体は、地域が違っても残す
      #   - 地域を選んでいない場合: キーワードに一致しない団体は落とす
      # 地域は area（住所・都道府県名）に LOCATION_ALIASES の語が含まれるかで判定する。
      def filter_roster_by_keyword_or_location(community_results, keyword, locations)
        keyword_terms = keyword.to_s.split(/[[:space:]]+/).reject(&:empty?)
        location_terms = locations.to_a.flat_map { |location| LOCATION_ALIASES[location] || [ location ] }

        community_results.select do |community_result|
          keyword_terms.any? { |term| community_result[:name].include?(term) } ||
            location_terms.any? { |term| community_result[:area].to_s.include?(term) }
        end
      end
    end
  end
end
