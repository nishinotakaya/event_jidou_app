module Research
  # Doomo（doomo.jp）のビジネス交流会スケジュール。
  # 経営者交流会・若手経営者交流会・士業交流会などを東京/大阪で定期開催している主催者で、
  # スケジュールページに schema.org の Event が JSON-LD で並ぶ（関西開催分もこのページに載る）。
  # 掲載されているのがビジネス交流会だけなので、キーワードでは絞らず開催予定を全件返す（場所指定のみ効かせる）。
  class DoomoService < BaseService
    SITE_KEY = "doomo".freeze
    SITE_LABEL = "Doomo".freeze
    SCHEDULE_URL = "https://doomo.jp/schedule/business-meetup-tokyo".freeze

    def search(_keyword, locations = [])
      filter_by_location(parse_events(http_get(SCHEDULE_URL)), locations)
    end

    private

    def parse_events(html)
      each_json_ld_event(parse_html(html)).filter_map do |event|
        event_url = event.dig("offers", "url").presence
        next if event_url.blank?

        build_result(
          title: event["name"],
          url: event_url,
          starts_at: parse_iso8601_datetime(event["startDate"]),
          datetime_text: format_datetime_text(event["startDate"]),
          venue: event.dig("location", "area"),
          organizer: event.dig("organizer", "name"),
          image_url: event["image"],
        )
      end
    end
  end
end
