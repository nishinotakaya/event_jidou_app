require 'net/http'
require 'uri'
require 'securerandom'

module Posting
  # BIZee（bizee.jp/seminar/）への投稿自動化。
  #
  # アーキテクチャ:
  #   - WordPress + Ultimate Member（ログイン） + WP Frontend Posting Plugin（投稿）
  #   - reCAPTCHA / Google ログイン無し → Net::HTTP のみで完結
  #   - email/password は ServiceConnection.credentials_for('bizee') から取得
  #
  # フロー:
  #   1. GET /seminar/b-login → _wpnonce と form_id を抽出
  #   2. POST /seminar/b-login（form-encoded） → セッション Cookie 取得
  #   3. GET /seminar/b-entry-2 → frontend-form-1_nonce を抽出
  #   4. POST /seminar/wp-admin/admin-ajax.php（multipart） → 記事作成
  class BizeeService < BaseService
    BASE_URL    = 'https://bizee.jp'.freeze
    LOGIN_PATH  = '/seminar/b-login'.freeze
    ENTRY_PATH  = '/seminar/b-entry-2'.freeze
    AJAX_PATH   = '/seminar/wp-admin/admin-ajax.php'.freeze

    # 「資格・キャリア・スキルアップ」カテゴリ。実機解析で 18 を確認済み。
    DEFAULT_CATEGORY_ID = '18'.freeze

    private

    def execute(_page, content, ef)
      login!
      result_url = create_event(content, ef)
      log("[BIZee] ✅ 処理完了 → #{result_url}")
      # BIZee は作成と同時に WordPress に公開される（下書きフラグなし）
      @published = true
      result_url
    end

    # ===== ログイン =====
    def login!
      creds = ServiceConnection.credentials_for('bizee')
      raise '[BIZee] メールアドレスが未設定です' if creds[:email].blank?
      raise '[BIZee] パスワードが未設定です' if creds[:password].blank?

      log('[BIZee] ログインページ取得 → nonce / form_id 抽出')
      page = http_get(LOGIN_PATH)
      html = page.body.to_s
      nonce = extract_um_login_nonce(html)
      form_id = extract_um_form_id(html)
      raise '[BIZee] ログインフォームの _wpnonce が取得できません' if nonce.blank?
      raise '[BIZee] ログインフォームの form_id が取得できません' if form_id.blank?

      log("[BIZee] ログイン送信中（form_id=#{form_id}）...")
      body = URI.encode_www_form(
        "username-#{form_id}"      => creds[:email],
        "user_password-#{form_id}" => creds[:password],
        'form_id'                  => form_id,
        'um_request'               => '',
        '_wpnonce'                 => nonce,
        '_wp_http_referer'         => LOGIN_PATH,
        'rememberme'               => '1',
      )
      res = http_post(LOGIN_PATH, body, content_type: 'application/x-www-form-urlencoded')
      follow_redirects(res)

      unless logged_in?
        raise '[BIZee] ログイン失敗（wordpress_logged_in_* Cookie が立ちません。メール/パスワードを確認してください）'
      end
      log('[BIZee] ✅ ログイン完了')
    end

    # ===== イベント投稿 =====
    def create_event(content, ef)
      log("[BIZee] 投稿フォーム取得 → frontend-form-1_nonce 抽出 (#{ENTRY_PATH})")
      entry = http_get(ENTRY_PATH)
      entry = follow_redirects(entry)
      nonce = extract_frontend_form_nonce(entry.body.to_s)
      raise '[BIZee] frontend-form-1_nonce が取得できません（ログイン切れの可能性）' if nonce.blank?

      title = extract_title(ef, content, 80)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      deadline   = ef['deadline'].presence || (Date.parse(start_date) - 1).strftime('%Y-%m-%d')
      year       = start_date.split('-').first
      place      = ef['place'].presence || 'オンライン'
      is_online  = place.include?('オンライン')
      online_label = is_online ? 'オンライン' : 'リアル（オフライン）'
      cost_label   = (ef['cost'].presence == '有料') ? '有料' : '無料'
      zoom_url   = ef['zoomUrl'].presence || ''
      organizer  = ef['organizer'].presence || '個人事業主・自営業者'
      prefecture = is_online ? 'オンライン' : (ef['prefecture'].presence || '東京都')
      category_id = (ef['bizeeCategoryId'].presence || DEFAULT_CATEGORY_ID).to_s

      plain_content = content.to_s.gsub(/<[^>]+>/, '').strip

      fields = {
        'post_data[post_title]'     => title,
        'post_data[post_content]'   => plain_content,
        'post_data[post_excerpt]'   => '',
        'post_data[thumbnail]'      => '',
        'post_data_thumbnail_file_input' => '',
        'post_data[taxonomy_terms][category][]' => category_id,
        'post_data[taxonomy_terms][post_tag]'   => '',
        'post_data[custom_field][list_seminar-url]'         => zoom_url,
        'post_data[custom_field][list_seminar-firstday]'    => start_date,
        'post_data[custom_field][_expiration-date]'         => year,
        'post_data[custom_field][list_seminar-lastday]'     => '[custom-end-date]',
        'post_data[custom_field][list_seminar-time]'        => start_time,
        'post_data[custom_field][list_seminar-deadline]'    => deadline,
        'post_data[custom_field][list_user-organizer]'      => organizer,
        'post_data[custom_field][list_user-company]'        => '[custom-user]',
        'post_data[custom_field][list_seminar-postcode]'    => '',
        'post_data[custom_field][list_seminar-prefectures]' => prefecture,
        'post_data[custom_field][list_seminar-address]'     => is_online ? '' : place,
        'post_data[custom_field][list_seminar-station]'     => '',
        'post_data[custom_field][list_seminar-number]'      => '',
        'post_data[custom_field][list_seminar-online]'      => online_label,
        'post_data[custom_field][list_seminar-cost]'        => cost_label,
        'post_data[custom_field][list_seminar-value]'       => '',
        'post_data[custom_field][list_seminar-subvalue]'    => '',
        'post_data[custom_field][list_teacher-name]'        => ef['teacherName'].to_s,
        'post_data[custom_field][list_teacher-profile]'     => ef['teacherProfile'].to_s,
        'post_data[ID]'             => '',
        'post_data[post_type]'      => 'post',
        'form_db_id'                => '1',
        'action'                    => 'wpfepp_handle_submission',
        'frontend-form-1_nonce'     => nonce,
        'form_id'                   => 'frontend-form-1',
        'submit_button'             => 'submit-form',
      }

      # 実機 curl と互換のため boundary は "----WebKit..." 形式（先頭4ダッシュ込）。
      # 本体側の区切りは "--" + boundary = "------WebKit..." となる。
      boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
      body = build_multipart(fields, boundary)
      log('[BIZee] イベント送信中（multipart admin-ajax.php）...')
      res = http_post(AJAX_PATH, body,
                      content_type: "multipart/form-data; boundary=#{boundary}",
                      ajax: true,
                      referer: "#{BASE_URL}#{ENTRY_PATH}")
      raise "[BIZee] 投稿失敗 (HTTP #{res.code}): #{res.body.to_s[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

      json = (JSON.parse(res.body) rescue nil)
      if json.is_a?(Hash)
        if json['success'] == false
          raise "[BIZee] 投稿エラー: #{json['data'] || json}"
        end
        post_id = json.dig('data', 'post_id') || json['post_id']
        permalink = json.dig('data', 'permalink') || json['permalink']
        log("[BIZee] ✅ 投稿成功 post_id=#{post_id}") if post_id
        return permalink if permalink
      end
      log("[BIZee] ✅ 投稿レスポンス: #{res.body.to_s[0, 200]}")
      "#{BASE_URL}/seminar/b-profile/#{username_from_cookie || 'me'}"
    end

    # ===== nonce / form_id 抽出 =====

    def extract_um_login_nonce(html)
      m = html.match(/name="_wpnonce"[^>]*?\bvalue="([a-f0-9]{6,})"/) ||
          html.match(/\bvalue="([a-f0-9]{6,})"[^>]*?name="_wpnonce"/) ||
          html.match(/"_wpnonce"\s*:\s*"([a-f0-9]{6,})"/)
      m&.captures&.first
    end

    def extract_um_form_id(html)
      m = html.match(/name="form_id"\s+value="(\d+)"/) ||
          html.match(/name="username-(\d+)"/)
      m&.captures&.first
    end

    def extract_frontend_form_nonce(html)
      # 実 HTML 例:
      #   <input name="frontend-form-1_nonce" id="frontend-form-1-nonce"
      #          class="frontend-form-1-nonce" value="a49ee79c8d">
      # name は underscore、id/class は hyphen。name と value の間に他属性が挟まる。
      m = html.match(/name="frontend-form-1_nonce"[^>]*?\bvalue="([a-f0-9]{6,})"/) ||
          html.match(/name="frontend-form-1-nonce"[^>]*?\bvalue="([a-f0-9]{6,})"/) ||
          html.match(/\bvalue="([a-f0-9]{6,})"[^>]*?name="frontend-form-1_nonce"/) ||
          html.match(/"frontend-form-1[-_]nonce"\s*:\s*"([a-f0-9]{6,})"/)
      m&.captures&.first
    end

    def logged_in?
      @cookies ||= {}
      @cookies.keys.any? { |k| k.to_s.start_with?('wordpress_logged_in_') }
    end

    def username_from_cookie
      @cookies ||= {}
      key = @cookies.keys.find { |k| k.to_s.start_with?('wordpress_logged_in_') }
      return nil unless key
      decoded = URI.decode_www_form_component(@cookies[key].to_s)
      decoded.split('|').first
    end

    # ===== multipart 組み立て =====

    def build_multipart(fields, boundary)
      # boundary は declared 値（"----WebKit..."）。on-wire 区切りは "--" + boundary。
      delimiter = "--#{boundary}"
      lines = []
      fields.each do |name, value|
        lines << delimiter
        lines << %(Content-Disposition: form-data; name="#{name}")
        lines << ''
        lines << value.to_s
      end
      lines << "#{delimiter}--"
      lines << ''
      lines.join("\r\n")
    end

    # ===== HTTP =====

    def http_get(path)
      uri = URI("#{BASE_URL}#{path}")
      req = Net::HTTP::Get.new(uri)
      set_headers(req)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
        res = http.request(req)
        merge_cookies(res)
        res
      end
    end

    def http_post(path, body, content_type:, ajax: false, referer: nil)
      uri = URI("#{BASE_URL}#{path}")
      req = Net::HTTP::Post.new(uri)
      req.body = body
      req['Content-Type'] = content_type
      req['X-Requested-With'] = 'XMLHttpRequest' if ajax
      req['Referer'] = referer if referer
      set_headers(req)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
        res = http.request(req)
        merge_cookies(res)
        res
      end
    end

    def set_headers(req)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36'
      req['Accept'] = req['Accept'] || 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      req['Accept-Language'] = 'ja,en-US;q=0.9,en;q=0.8'
      req['Origin'] = BASE_URL
      req['Cookie'] = cookie_header if @cookies&.any?
    end

    def merge_cookies(response)
      @cookies ||= {}
      Array(response.get_fields('set-cookie')).each do |raw|
        name, value = raw.split(';').first.split('=', 2)
        @cookies[name.strip] = value.to_s.strip
      end
    end

    def cookie_header
      @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
    end

    def follow_redirects(response, max_redirects: 5)
      count = 0
      current = response
      while current.is_a?(Net::HTTPRedirection) && count < max_redirects
        location = current['location']
        location = "#{BASE_URL}#{location}" unless location.start_with?('http')
        current = http_get(URI(location).path + (URI(location).query ? "?#{URI(location).query}" : ''))
        count += 1
      end
      current
    end
  end
end
