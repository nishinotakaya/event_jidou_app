require 'net/http'
require 'uri'
require 'json'

module Posting
  class TunagateService < BaseService
    BASE_URL    = 'https://tunagate.com'
    SIGN_IN_URL = "#{BASE_URL}/users/sign_in"

    private

    def execute(_page, content, ef)
      setup_session!
      event_url = create_event(content, ef)
      log("[つなゲート] ✅ イベント作成完了 → #{event_url}")
      event_url
    end

    # ----------------------------------------------------------------
    # セッション管理
    # ----------------------------------------------------------------

    def setup_session!
      @cookies = {}
      @csrf_token = nil

      conn = ServiceConnection.find_by(service_name: 'tunagate')

      # 1) session_data（ブラウザログインで取得済みCookie）を復元
      if conn&.session_data.present?
        restore_cookies_from_session_data(conn.session_data)
        if verify_login
          log('[つなゲート] ✅ 保存済みセッションで認証OK')
          return
        end
        log('[つなゲート] 保存済みセッション期限切れ、再ログイン試行...')
      end

      # 2) メール/パスワードでDeviseフォームログイン
      creds = ServiceConnection.credentials_for('tunagate')
      email    = creds[:email].presence
      password = creds[:password].presence

      if email && password
        form_login!(email, password)
        if verify_login
          log('[つなゲート] ✅ フォームログイン成功')
          save_session_cookies!(conn)
          return
        end
      end

      raise '[つなゲート] ログインできません。接続管理画面から「ブラウザログイン」でログインしてください。'
    end

    # Playwrightのstorage_state JSONからCookieを復元
    def restore_cookies_from_session_data(json_str)
      data = JSON.parse(json_str) rescue {}
      cookies_array = data['cookies'] || []
      cookies_array.each do |c|
        next unless c['domain']&.include?('tunagate.com')
        @cookies[c['name']] = c['value']
      end
    end

    # ログイン済みかどうかをGETリクエストで確認
    def verify_login
      res = http_get('/menu')
      # ログイン済みなら200でメニューページ、未ログインならsign_inにリダイレクト
      return false if res.is_a?(Net::HTTPRedirection) && res['location']&.include?('sign_in')
      return false unless res.is_a?(Net::HTTPSuccess)
      return false if res.body&.include?('sign_in')

      # CSRFトークンも取得
      extract_csrf_token(res.body)
      true
    end

    # Deviseフォームログイン
    def form_login!(email, password)
      # 1) sign_inページからCSRFトークンを取得
      res = http_get('/users/sign_in')
      follow_redirects!(res)
      merge_cookies(res)
      extract_csrf_token(res.body) if res.body

      raise '[つなゲート] CSRFトークンが取得できません' unless @csrf_token

      # 2) ログインPOST
      form_data = URI.encode_www_form(
        'authenticity_token' => @csrf_token,
        'user[email]'        => email,
        'user[password]'     => password,
        'user[remember_me]'  => '1',
        'commit'             => 'ログイン'
      )

      res = http_post('/users/sign_in', form_data, content_type: 'application/x-www-form-urlencoded')
      merge_cookies(res)

      # リダイレクト先を追跡
      if res.is_a?(Net::HTTPRedirection)
        location = res['location']
        if location&.include?('sign_in')
          raise '[つなゲート] ログイン失敗（メールアドレスまたはパスワードが正しくありません）'
        end
        res = http_get(URI(location).path)
        merge_cookies(res)
        extract_csrf_token(res.body) if res.body
      end
    end

    # セッションCookieをDBに保存
    def save_session_cookies!(conn)
      return unless conn

      cookies_array = @cookies.map do |name, value|
        { 'name' => name, 'value' => value, 'domain' => '.tunagate.com', 'path' => '/' }
      end
      session_json = { 'cookies' => cookies_array, 'origins' => [] }.to_json
      conn.update(session_data: session_json, status: 'connected', last_connected_at: Time.current, error_message: nil)
    end

    # ----------------------------------------------------------------
    # イベント作成
    # ----------------------------------------------------------------

    def create_event(content, ef)
      circle_id = AppSetting.get('tunagate_circle_id').presence || '220600'
      title     = extract_title(ef, content, 100)

      # 1) イベント作成ページにアクセス → リダイレクトでevent_idを取得
      log("[つなゲート] イベント作成中: #{title}")
      event_id = create_event_page(circle_id)
      log("[つなゲート] イベントID取得: #{event_id}")

      # 2) CSRFトークンを編集ページから取得
      edit_url = "/event/edit/#{event_id}"
      res = http_get(edit_url)
      merge_cookies(res)
      extract_csrf_token(res.body) if res.body

      # 3) 説明文（content）を作成
      create_content(event_id, content)

      # 4) イベント情報をまとめて保存（draft or publish）
      publish = ef.dig('publishSites', 'つなゲート')
      save_event(event_id, title, content, ef, publish: publish)

      # イベントURL
      "#{BASE_URL}/circle/#{circle_id}/events/#{event_id}"
    end

    # GET /events/new/{circle_id} → リダイレクトで /event/edit/{event_id} になる
    def create_event_page(circle_id)
      res = http_get("/events/new/#{circle_id}")
      merge_cookies(res)

      # リダイレクト先からevent_idを抽出
      location = res['location'] || ''
      if res.is_a?(Net::HTTPRedirection)
        match = location.match(%r{/event/edit/(\d+)})
        return match[1] if match

        # リダイレクト先をさらに追跡
        res2 = http_get(URI(location).path)
        merge_cookies(res2)
        extract_csrf_token(res2.body) if res2.body
        # URLからevent_idを探す
        match = location.match(%r{/events?/(?:edit/)?(\d+)})
        return match[1] if match
      end

      # レスポンスボディからevent_idを探す（リダイレクト後のページ）
      if res.body
        match = res.body.match(%r{/event/edit/(\d+)})
        return match[1] if match

        # meta refresh等
        match = res.body.match(%r{event_id['":\s]+(\d+)})
        return match[1] if match
      end

      raise '[つなゲート] イベントIDを取得できませんでした'
    end

    # POST /api/event_edit/create_content
    def create_content(event_id, content)
      body = {
        event_id: event_id.to_i,
        body: content,
        content_type: 1,
      }
      res = api_post('/api/event_edit/create_content', body)
      log('[つなゲート] 説明文作成完了')
      res
    end

    # POST /api/event_edit_submit/draft or /api/event_edit_submit/publish
    def save_event(event_id, title, content, ef, publish: false)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'].presence || '20:30')
      end_time   = pad_time(ef['endTime'].presence || '21:30')
      is_online  = ef['place']&.include?('オンライン')
      capacity   = (ef['capacity'].presence || '50').to_i
      zoom_url   = ef['zoomUrl'].to_s

      event_datetime = "#{start_date} #{start_time}:00"
      end_datetime   = "#{start_date} #{end_time}:00"

      body = {
        event: {
          id: event_id.to_i,
          title: title,
          contents: content,
          circle_id: @circle_id || AppSetting.get('tunagate_circle_id').presence || '220600',
          event_date: event_datetime,
          event_end_datetime: end_datetime,
          is_draft: !publish,
          pref_id: 13,
          city_id: 0,
          delete_status: 0,
          is_application_allowed: true,
          is_publicity: true,
          is_online: is_online || false,
          online_url: is_online ? zoom_url : nil,
          covid_description: '',
          place: nil,
          place_detail: nil,
          is_display_place_detail: true,
          meeting_pref_id: 13,
          meeting_place: nil,
          capacity: nil,
          min_num_of_people: 1,
        },
        events_plans: [{
          event_id: event_id.to_i,
          plan: '無料参加',
          capacity: capacity,
          creator_price: 0,
          price_type: 3,
          payment_type: 0,
          is_application_allowed: true,
          target_type: 2,
          is_publicity: false,
          is_deleted: false,
        }],
      }

      res =
        if publish
          submit_publish(body)
        else
          api_post('/api/event_edit_submit/draft', body)
        end
      status = publish ? '公開' : '下書き'
      log("[つなゲート] イベント#{status}保存完了")
      res
    end

    # /publish が 404 を返すケースに備えて /draft（is_draft: false）へフォールバック
    def submit_publish(body)
      api_post('/api/event_edit_submit/publish', body)
    rescue => e
      raise unless e.message.include?('404')
      log('[つなゲート] ⚠️ /publish が 404 → /draft(is_draft:false) にフォールバック')
      body = body.deep_dup
      body[:event][:is_draft] = false
      api_post('/api/event_edit_submit/draft', body)
    end

    # ----------------------------------------------------------------
    # 削除・中止
    # ----------------------------------------------------------------

    def perform_delete(_page, event_url)
      setup_session!
      event_id = extract_event_id(event_url)
      raise '[つなゲート] イベントIDが特定できません' unless event_id

      body = {
        event: {
          id: event_id.to_i,
          delete_status: 1,
          is_draft: true,
          circle_id: @circle_id || AppSetting.get('tunagate_circle_id').presence || '220600',
          title: '',
          pref_id: 13,
          city_id: 0,
        },
        events_plans: [{
          event_id: event_id.to_i,
          plan: '参加',
          capacity: 1,
          creator_price: 0,
          price_type: 3,
          payment_type: 0,
          is_application_allowed: true,
          target_type: 2,
          is_publicity: false,
          is_deleted: false,
        }],
      }
      api_post('/api/event_edit_submit/draft', body)
      log("[つなゲート] ✅ イベント削除完了: #{event_id}")
    rescue => e
      log("[つなゲート] 削除エラー: #{e.message}")
      raise
    end

    def perform_cancel(_page, event_url)
      # つなゲートではキャンセル = 削除として扱う
      perform_delete(_page, event_url)
    end

    def perform_publish(_page, event_url)
      setup_session!
      event_id = extract_event_id(event_url)
      raise '[つなゲート] イベントIDが特定できません' unless event_id

      body = { event_id: event_id.to_i }
      api_post('/api/event_edit_submit/publish', body)
      log("[つなゲート] ✅ イベント公開完了: #{event_id}")
    rescue => e
      log("[つなゲート] 公開エラー: #{e.message}")
      raise
    end

    # ----------------------------------------------------------------
    # HTTP通信ヘルパー
    # ----------------------------------------------------------------

    def http_get(path)
      uri = URI("#{BASE_URL}#{path}")
      req = Net::HTTP::Get.new(uri)
      set_common_headers(req)
      req['Cookie'] = cookie_header

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.open_timeout = 15
        http.read_timeout = 30
        res = http.request(req)
        merge_cookies(res)
        res
      end
    end

    def http_post(path, body, content_type: nil)
      uri = URI("#{BASE_URL}#{path}")
      req = Net::HTTP::Post.new(uri)
      set_common_headers(req)
      req['Cookie'] = cookie_header
      req['X-CSRF-Token'] = @csrf_token if @csrf_token
      req.body = body

      if content_type
        req['Content-Type'] = content_type
      end

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.open_timeout = 15
        http.read_timeout = 30
        res = http.request(req)
        merge_cookies(res)
        res
      end
    end

    def api_post(path, body)
      uri = URI("#{BASE_URL}#{path}")
      req = Net::HTTP::Post.new(uri)
      set_common_headers(req)
      req['Cookie'] = cookie_header
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req['X-CSRF-Token'] = @csrf_token if @csrf_token
      req['X-Requested-With'] = 'XMLHttpRequest'
      req.body = body.to_json

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.open_timeout = 15
        http.read_timeout = 30
        http.request(req)
      end
      merge_cookies(res)

      unless res.is_a?(Net::HTTPSuccess)
        raise "[つなゲート] API エラー: #{res.code} #{res.message} (#{path}) body=#{res.body&.truncate(200)}"
      end

      JSON.parse(res.body) rescue {}
    end

    def set_common_headers(req)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
      req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      req['Accept-Language'] = 'ja,en-US;q=0.9,en;q=0.8'
    end

    def cookie_header
      @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
    end

    def merge_cookies(res)
      return unless res

      Array(res.get_fields('set-cookie')).each do |sc|
        name, value = sc.split(';').first.split('=', 2)
        @cookies[name.strip] = value.to_s.strip if name
      end
    end

    def extract_csrf_token(html)
      return unless html

      match = html.match(/<meta\s+name="csrf-token"\s+content="([^"]+)"/)
      match ||= html.match(/<meta\s+content="([^"]+)"\s+name="csrf-token"/)
      @csrf_token = match[1] if match
    end

    def follow_redirects!(res, limit: 5)
      count = 0
      while res.is_a?(Net::HTTPRedirection) && count < limit
        location = res['location']
        break unless location

        path = location.start_with?('http') ? URI(location).path : location
        res = http_get(path)
        count += 1
      end
      res
    end

    def extract_event_id(url)
      match = url.to_s.match(%r{/events?/(?:edit/)?(\d+)})
      match ||= url.to_s.match(%r{circle/\d+/events/(\d+)})
      match&.[](1)
    end
  end
end
