require 'google/apis/calendar_v3'
require 'googleauth'

class GoogleCalendarService
  CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar'

  def initialize(user)
    @user = user
    raise 'Googleアカウントが未連携です' unless @user&.google_access_token.present?
  end

  # 指定期間のイベント一覧を取得
  def list_events(time_min:, time_max:, max_results: 100)
    service = build_service
    result = service.list_events(
      'primary',
      time_min: time_min.iso8601,
      time_max: time_max.iso8601,
      max_results: max_results,
      single_events: true,
      order_by: 'startTime',
    )
    (result.items || []).map { |e| serialize_event(e) }
  end

  # イベントを作成
  def create_event(title:, description: '', start_time:, end_time:, location: nil)
    service = build_service
    event = Google::Apis::CalendarV3::Event.new(
      summary: title,
      description: description,
      location: location,
      start: build_event_datetime(start_time),
      end: build_event_datetime(end_time),
    )
    created = service.insert_event('primary', event)
    serialize_event(created)
  end

  # イベントを更新
  def update_event(event_id, title: nil, start_time: nil, end_time: nil, description: nil, location: nil)
    service = build_service
    event = service.get_event('primary', event_id)
    event.summary = title if title.present?
    event.description = description if description.present?
    event.location = location if location.present?
    event.start = build_event_datetime(start_time) if start_time.present?
    event.end = build_event_datetime(end_time) if end_time.present?
    updated = service.update_event('primary', event_id, event)
    serialize_event(updated)
  end

  # イベントを削除
  def delete_event(event_id)
    service = build_service
    service.delete_event('primary', event_id)
    true
  end

  private

  def build_service
    cal = Google::Apis::CalendarV3::CalendarService.new
    cal.authorization = build_credentials
    cal
  end

  def build_credentials
    creds = Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV['GOOGLE_CLIENT_SECRET'],
      scope: [CALENDAR_SCOPE],
      additional_parameters: { access_type: 'offline' },
    )
    creds.access_token = @user.google_access_token
    creds.refresh_token = @user.google_refresh_token
    creds.expires_at = @user.google_token_expires_at

    if @user.google_token_expires_at && Time.current > @user.google_token_expires_at
      creds.fetch_access_token!
      @user.update!(
        google_access_token: creds.access_token,
        google_token_expires_at: Time.at(creds.issued_at.to_i + creds.expires_in.to_i),
      )
    end

    creds
  end

  def build_event_datetime(time)
    if time.is_a?(String)
      time = Time.zone.parse(time)
    end
    Google::Apis::CalendarV3::EventDateTime.new(
      date_time: time.iso8601,
      time_zone: 'Asia/Tokyo',
    )
  end

  def serialize_event(event)
    start_dt = event.start&.date_time || event.start&.date
    end_dt = event.end&.date_time || event.end&.date
    {
      id: event.id,
      title: event.summary,
      description: event.description,
      location: event.location,
      start: start_dt&.to_s,
      end: end_dt&.to_s,
      htmlLink: event.html_link,
      allDay: event.start&.date.present?,
    }
  end
end
