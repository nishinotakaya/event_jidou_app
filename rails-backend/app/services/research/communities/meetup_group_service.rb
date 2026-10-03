module Research
  module Communities
    # Meetup グループ（meetup.com/find/?source=GROUPS）の検索。
    # ページ内の #__NEXT_DATA__ にある Apollo キャッシュ（Group:<id> / PhotoInfo:<id>）を読む。
    # 地域は MeetupService と同じ LOCATION_SLUGS で都市に読み替え、未選択なら東京。
    # 地域ごとに 1 リクエストを並列で投げ、隣接地域で重なるグループは url で重複除去する。
    # 非公開（isPrivate）のグループも、検索結果に出るものは拾う。
    class MeetupGroupService < BaseService
      SITE_KEY = "meetup_group".freeze
      SITE_LABEL = "Meetup グループ".freeze
      BASE_URL = "https://www.meetup.com".freeze
      GROUP_PHOTO_SIZE = "676x380.webp".freeze

      def search(keyword, locations = [])
        fetches = location_slugs(locations).map { |location_slug| fetch_in_background(keyword, location_slug) }
        fetches.flat_map(&:value).uniq { |community_result| community_result[:url] }
      end

      private

      # Thread#value が失敗を呼び出し元へ投げ直すので、二重に記録されないよう自動出力だけ止める（MeetupService と同じ）
      def fetch_in_background(keyword, location_slug)
        Thread.new { parse_search_page(http_get(search_url(keyword, location_slug))) }
          .tap { |thread| thread.report_on_exception = false }
      end

      def location_slugs(locations)
        selected_locations = locations.presence || [ Research::MeetupService::DEFAULT_LOCATION ]
        selected_locations.filter_map { |location| Research::MeetupService::LOCATION_SLUGS[location] }.uniq
      end

      def search_url(keyword, location_slug)
        params = { source: "GROUPS", keywords: keyword, location: location_slug }
        "#{BASE_URL}/find/?#{params.to_query}"
      end

      def parse_search_page(html)
        apollo_state = extract_apollo_state(html)

        apollo_state.each_with_object([]) do |(cache_key, entry), community_results|
          next unless cache_key.start_with?("Group:") && entry.is_a?(Hash)
          next if entry["name"].blank? || entry["link"].blank?

          community_results << build_community_result(
            name: entry["name"],
            url: entry["link"],
            description: entry["description"],
            area: entry["city"],
            member_count: entry.dig("stats", "memberCounts", "all")&.to_i,
            image_url: group_image_url(apollo_state, entry)
          )
        end
      end

      def extract_apollo_state(html)
        next_data_json = parse_html(html).at_css("script#__NEXT_DATA__")&.text
        return {} if next_data_json.blank?

        JSON.parse(next_data_json).dig("props", "pageProps", "__APOLLO_STATE__") || {}
      rescue JSON::ParserError
        {}
      end

      # groupPhoto は PhotoInfo への参照。写真の無いグループは null になる
      def group_image_url(apollo_state, group_entry)
        photo_reference = group_entry.dig("groupPhoto", "__ref")
        photo_entry = photo_reference && apollo_state[photo_reference]
        return nil if photo_entry.blank? || photo_entry["baseUrl"].blank? || photo_entry["id"].blank?

        "#{photo_entry['baseUrl']}#{photo_entry['id']}/#{GROUP_PHOTO_SIZE}"
      end
    end
  end
end
