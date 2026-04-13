require 'net/http'
require 'uri'

module Posting
  class DoorkeeperService < BaseService
    BASE_URL = 'https://manage.doorkeeper.jp'

    private

    # ===== メインフロー =====
    def execute(_page, content, ef)
      login!
      event_url = create_event(content, ef)

      if ef.dig('publishSites', 'Doorkeeper')
        publish_event_via_api(event_url)
      else
        log('[Doorkeeper] 公開設定: 非公開（下書き保存のみ）')
      end

      log("[Doorkeeper] ✅ 処理完了 → #{event_url}")
      event_url
    end

    # ===== ログイン =====
    def login!
      creds = ServiceConnection.credentials_for('doorkeeper')
      raise '[Doorkeeper] メールアドレスが未設定です' if creds[:email].blank?

      # ログインページからCSRFトークンを取得
      log('[Doorkeeper] ログインページからCSRFトークン取得...')
      login_page = http_get('/user/sign_in')
      csrf_token = extract_csrf_token(login_page.body)
      raise '[Doorkeeper] CSRFトークンが取得できません' if csrf_token.blank?

      # Cookie保持用のストアを初期化
      @cookies = extract_cookies(login_page)

      # ログインPOST
      log('[Doorkeeper] ログイン実行中...')
      login_body = URI.encode_www_form({
        'authenticity_token' => csrf_token,
        'user[email]'        => creds[:email],
        'user[password]'     => creds[:password],
        'user[remember_me]'  => '1',
      })

      login_res = http_post('/user/sign_in', login_body, content_type: 'application/x-www-form-urlencoded')
      merge_cookies(login_res)

      # リダイレクト先をたどる（302/303）
      follow_redirects(login_res)

      # ログイン確認: グループ一覧にアクセスしてみる
      check_res = http_get('/groups')
      follow_redirects(check_res)

      if check_res.is_a?(Net::HTTPSuccess) || check_res.is_a?(Net::HTTPRedirection)
        log('[Doorkeeper] ✅ ログイン完了')
      else
        raise "[Doorkeeper] ログイン失敗 (HTTP #{check_res.code})"
      end
    end

    # ===== イベント作成 =====
    def create_event(content, ef)
      group_name = AppSetting.get('doorkeeper_group_name').presence || ENV['DOORKEEPER_GROUP_NAME'].to_s
      raise '[Doorkeeper] DOORKEEPER_GROUP_NAME が未設定です（AppSetting or ENV）' if group_name.blank?

      # 新規イベントページからCSRFトークンを取得
      new_event_path = "/groups/#{group_name}/events/new"
      log("[Doorkeeper] イベント作成ページからCSRFトークン取得: #{new_event_path}")
      new_page = http_get(new_event_path)
      follow_redirects(new_page)
      csrf_token = extract_csrf_token(new_page.body)
      raise '[Doorkeeper] イベント作成ページのCSRFトークンが取得できません' if csrf_token.blank?

      # イベントデータ組み立て
      title = extract_title(ef, content, 100)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      s_year, s_month, s_day = start_date.split('-')
      e_year, e_month, e_day = end_date.split('-')
      sh, sm = start_time.split(':')
      eh, em = end_time.split(':')

      # 5分刻みに丸める
      sm_rounded = (sm.to_i / 5 * 5).to_s.rjust(2, '0')
      em_rounded = (em.to_i / 5 * 5).to_s.rjust(2, '0')

      place = ef['place'].presence || 'オンライン'
      is_online = place.include?('オンライン')
      zoom_url = ef['zoomUrl'].presence || 'https://us02web.zoom.us/j/example'
      capacity = ef['capacity'].presence || '50'

      form_data = {
        'authenticity_token' => csrf_token,
        'event[title_ja]' => title,
        'event[starts_at_date]' => start_date.gsub('-', '/'),
        'event[starts_at_time(1i)]' => s_year,
        'event[starts_at_time(2i)]' => s_month.to_i.to_s,
        'event[starts_at_time(3i)]' => s_day.to_i.to_s,
        'event[starts_at_time(4i)]' => sh.to_i.to_s,
        'event[starts_at_time(5i)]' => sm_rounded,
        'event[ends_at_date]' => end_date.gsub('-', '/'),
        'event[ends_at_time(1i)]' => e_year,
        'event[ends_at_time(2i)]' => e_month.to_i.to_s,
        'event[ends_at_time(3i)]' => e_day.to_i.to_s,
        'event[ends_at_time(4i)]' => eh.to_i.to_s,
        'event[ends_at_time(5i)]' => em_rounded,
        'event[attendance_type]' => is_online ? 'online' : 'in_person',
        'event[description_ja]' => content,
        'event[ticket_types_attributes][0][admission_type]' => 'free',
        'event[ticket_types_attributes][0][description_ja]' => 'オンラインチケット',
        'event[ticket_types_attributes][0][ticket_limit]' => capacity.to_s,
        'commit' => '作成する',
      }
      form_data['event[online_event_url]'] = zoom_url if is_online

      log("[Doorkeeper] イベント作成POST: #{title}")
      create_path = "/groups/#{group_name}/events"
      body = URI.encode_www_form(form_data)
      create_res = http_post(create_path, body, content_type: 'application/x-www-form-urlencoded')
      merge_cookies(create_res)

      # 成功時は302リダイレクト → イベント管理ページへ
      event_url = if create_res.is_a?(Net::HTTPRedirection)
                    location = create_res['location']
                    location = "#{BASE_URL}#{location}" unless location.start_with?('http')
                    log("[Doorkeeper] ✅ イベント作成成功 → #{location}")
                    location
                  elsif create_res.is_a?(Net::HTTPSuccess)
                    # 200が返った場合、バリデーションエラーの可能性
                    if create_res.body.include?('error') || create_res.body.include?('エラー')
                      errors = create_res.body.scan(/<li[^>]*>([^<]+)<\/li>/).flatten
                      raise "[Doorkeeper] イベント作成エラー: #{errors.join(', ')}" if errors.any?
                    end
                    # URLから推定
                    log('[Doorkeeper] ✅ イベント作成成功（リダイレクトなし）')
                    "#{BASE_URL}#{create_path}"
                  else
                    raise "[Doorkeeper] イベント作成失敗 (HTTP #{create_res.code}): #{create_res.body[0, 500]}"
                  end

      event_url
    end

    # ===== 公開 =====
    def publish_event_via_api(event_url)
      log('[Doorkeeper] 公開処理を実行...')

      # イベント管理ページにアクセスして公開フォームを探す
      event_path = URI(event_url).path
      page_res = http_get(event_path)
      follow_redirects(page_res)

      csrf_token = extract_csrf_token(page_res.body)

      # 公開用のPATCHまたはPOSTエンドポイントを探す
      # Doorkeeperの公開は通常 /groups/{group}/events/{id}/publish
      publish_path = event_path.sub(%r{/edit\z}, '') + '/publish'

      body = URI.encode_www_form({
        'authenticity_token' => csrf_token,
        '_method' => 'patch',
      })

      publish_res = http_post(publish_path, body, content_type: 'application/x-www-form-urlencoded')
      merge_cookies(publish_res)

      if publish_res.is_a?(Net::HTTPRedirection) || publish_res.is_a?(Net::HTTPSuccess)
        log('[Doorkeeper] ✅ 公開完了')
      else
        log("[Doorkeeper] ⚠️ 公開に失敗した可能性があります (HTTP #{publish_res.code})")
      end
    end

    # ===== 削除 =====
    def perform_delete(_page, event_url)
      login!
      event_path = URI(event_url).path

      # 削除ページからCSRFトークン取得
      page_res = http_get(event_path)
      follow_redirects(page_res)
      csrf_token = extract_csrf_token(page_res.body)
      raise '[Doorkeeper] CSRFトークンが取得できません' if csrf_token.blank?

      body = URI.encode_www_form({
        'authenticity_token' => csrf_token,
        '_method' => 'delete',
      })

      delete_res = http_post(event_path, body, content_type: 'application/x-www-form-urlencoded')
      merge_cookies(delete_res)

      if delete_res.is_a?(Net::HTTPRedirection) || delete_res.is_a?(Net::HTTPSuccess)
        log('[Doorkeeper] ✅ イベント削除完了')
      else
        raise "[Doorkeeper] 削除失敗 (HTTP #{delete_res.code})"
      end
    end

    # ===== 中止 =====
    def perform_cancel(_page, event_url)
      login!
      event_path = URI(event_url).path
      cancel_path = event_path.sub(%r{/edit\z}, '') + '/cancel'

      page_res = http_get(event_path)
      follow_redirects(page_res)
      csrf_token = extract_csrf_token(page_res.body)
      raise '[Doorkeeper] CSRFトークンが取得できません' if csrf_token.blank?

      body = URI.encode_www_form({
        'authenticity_token' => csrf_token,
        '_method' => 'patch',
      })

      cancel_res = http_post(cancel_path, body, content_type: 'application/x-www-form-urlencoded')
      merge_cookies(cancel_res)

      if cancel_res.is_a?(Net::HTTPRedirection) || cancel_res.is_a?(Net::HTTPSuccess)
        log('[Doorkeeper] ✅ イベント中止完了')
      else
        raise "[Doorkeeper] 中止失敗 (HTTP #{cancel_res.code})"
      end
    end

    # ===== HTTP通信ヘルパー =====

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

    def http_post(path, body, content_type: 'application/x-www-form-urlencoded')
      uri = URI("#{BASE_URL}#{path}")
      req = Net::HTTP::Post.new(uri)
      req.body = body
      req['Content-Type'] = content_type
      set_headers(req)

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
        res = http.request(req)
        merge_cookies(res)
        res
      end
    end

    def set_headers(req)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
      req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      req['Accept-Language'] = 'ja,en-US;q=0.9,en;q=0.8'
      req['Cookie'] = cookie_header if @cookies&.any?
    end

    # ===== Cookie管理 =====

    def extract_cookies(response)
      cookies = {}
      Array(response.get_fields('set-cookie')).each do |raw|
        name, value = raw.split(';').first.split('=', 2)
        cookies[name.strip] = value.to_s.strip
      end
      cookies
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

    # ===== ユーティリティ =====

    def extract_csrf_token(html)
      # <meta name="csrf-token" content="..." />
      match = html.to_s.match(/<meta\s+name="csrf-token"\s+content="([^"]+)"/i)
      match ||= html.to_s.match(/<meta\s+content="([^"]+)"\s+name="csrf-token"/i)
      match&.captures&.first
    end

    def follow_redirects(response, max_redirects: 5)
      count = 0
      current = response
      while current.is_a?(Net::HTTPRedirection) && count < max_redirects
        location = current['location']
        location = "#{BASE_URL}#{location}" unless location.start_with?('http')
        current = http_get(URI(location).path)
        count += 1
      end
      current
    end
  end
end
