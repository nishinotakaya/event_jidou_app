require 'net/http'
require 'json'

module Posting
  class LumaService < BaseService
    API_BASE = 'https://api2.luma.com'
    CALENDAR_API_ID = 'cal-pAQcVXC34JzVcRE'

    private

    def execute(_page, content, ef)
      @auth_key = fetch_auth_key
      raise '[Luma] auth-session-keyがありません。接続管理画面からGoogleログインしてください。' unless @auth_key

      verify_login!
      event_api_id = create_event(content, ef)

      # 説明文を更新（create時にはdescription_mirrorのみ）
      update_description(event_api_id, content, ef) if event_api_id

      # 公開URLを取得（lu.ma/{slug}形式）
      event_data = api_get("/event/admin/get?event_api_id=#{event_api_id}")
      slug = event_data.dig('event', 'url')
      public_url = slug ? "https://lu.ma/#{slug}" : "https://luma.com/event/manage/#{event_api_id}"
      log("[Luma] ✅ イベント作成完了 → #{public_url}")
      public_url
    end

    def fetch_auth_key
      conn = ServiceConnection.find_by(service_name: 'luma')
      return nil unless conn&.session_data.present?

      data = JSON.parse(conn.session_data) rescue {}
      # auth_session_keyキーがあればそれを使う、なければcookiesから取得
      data['auth_session_key'] ||
        data['cookies']&.find { |c| c['name'] == 'luma.auth-session-key' }&.dig('value')
    end

    def verify_login!
      res = api_get('/calendar/admin/list')
      raise '[Luma] ログインセッションが無効です。再度Googleログインしてください。' unless res['infos']
      log('[Luma] ✅ API認証OK')
    end

    def create_event(content, ef)
      title = extract_title(ef, content, 100)
      start_date = ef['startDate'].presence || default_date_plus(30)
      start_time = pad_time(ef['startTime'].presence || '20:30')
      end_time = pad_time(ef['endTime'].presence || '21:30')

      # ISO 8601形式に変換（JST→UTC）
      start_dt = Time.parse("#{start_date} #{start_time} +0900")
      end_dt = Time.parse("#{start_date} #{end_time} +0900")
      duration_seconds = (end_dt - start_dt).to_i
      duration_hours = duration_seconds / 3600
      duration_minutes = (duration_seconds % 3600) / 60
      duration_interval = "PT#{duration_hours}H" + (duration_minutes > 0 ? "#{duration_minutes}M" : '')

      body = {
        name: title,
        start_at: start_dt.utc.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
        duration_interval: duration_interval,
        timezone: 'Asia/Tokyo',
        calendar_api_id: CALENDAR_API_ID,
        visibility: 'public',
        location_type: 'offline',
        geo_address_visibility: 'public',
        geo_address_json: nil,
        coordinate: nil,
        zoom_meeting_url: ef['zoomUrl'].to_s,
        zoom_meeting_id: '',
        zoom_meeting_password: '',
        zoom_session_type: nil,
        zoom_creation_method: nil,
        description_mirror: build_description(content),
        cover_url: 'https://images.lumacdn.com/gallery-images/lr/7abe3092-628a-42a3-b74e-4cfd56a4d79f',
        max_capacity: nil,
        waitlist_status: 'disabled',
        theme_meta: { theme: 'legacy' },
        tint_color: '#ea536d',
        font_title: 'ivy-presto',
        grant_manage_access: false,
        _calendar_requires_manage_access: false,
        supports_members_only: false,
        calendar_to_submit_to_api_id: nil,
        ticket_types: [{
          currency: nil,
          type: 'free',
          ethereum_token_requirements: [],
          cents: nil,
          is_flexible: false,
          min_cents: nil,
          require_approval: false,
          is_hidden: false,
        }],
      }

      log("[Luma] イベント作成中: #{title}")
      res = api_post('/event/create', body)

      event_api_id = res.dig('event', 'api_id') || res['api_id']
      raise "[Luma] イベント作成に失敗しました: #{res['message']}" unless event_api_id

      log("[Luma] イベント作成成功: #{event_api_id}")
      event_api_id
    end

    def update_description(event_api_id, content, ef)
      body = {
        event_api_id: event_api_id,
        description: content,
        description_mirror: build_description(content),
      }
      api_post('/event/update', body) rescue nil
    end

    def build_description(content)
      # Luma description_mirror: ProseMirror JSON形式（行ごとにparagraph）
      paragraphs = content.split("\n").map do |line|
        if line.strip.empty?
          { type: 'paragraph' }
        else
          { type: 'paragraph', content: [{ type: 'text', text: line }] }
        end
      end
      { type: 'doc', content: paragraphs }
    end

    # --- API通信 ---

    def api_get(path)
      uri = URI("#{API_BASE}#{path}")
      req = Net::HTTP::Get.new(uri)
      set_headers(req)

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      JSON.parse(res.body)
    end

    def api_post(path, body)
      uri = URI("#{API_BASE}#{path}")
      req = Net::HTTP::Post.new(uri)
      req.body = body.to_json
      set_headers(req)
      req['Content-Type'] = 'application/json'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      JSON.parse(res.body)
    end

    def set_headers(req)
      req['Cookie'] = "luma.auth-session-key=#{@auth_key}"
      req['x-luma-client-type'] = 'luma-web'
      req['Accept'] = '*/*'
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      @auth_key = fetch_auth_key
      return log('[Luma] auth-session-keyがありません') unless @auth_key

      event_api_id = event_url.scan(/evt-\w+/).first
      return log('[Luma] イベントIDが特定できません') unless event_api_id

      api_post('/event/admin/delete', { event_api_id: event_api_id })
      log("[Luma] ✅ イベント削除完了: #{event_api_id}")
    rescue => e
      log("[Luma] 削除エラー: #{e.message}")
    end

    def perform_cancel(page, event_url)
      perform_delete(page, event_url)
    end
  end
end
