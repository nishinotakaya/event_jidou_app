require 'net/http'
require 'nokogiri'
require 'playwright'
require 'shellwords'

# 各サイトのイベントページから申し込み数をスクレイピング
# 非公開（下書き）イベントはPlaywrightでログイン後にチェック
class RegistrationChecker
  USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'

  def self.check_all(item_id)
    histories = PostingHistory.where(item_id: item_id, status: 'success')
      .where.not(event_url: [nil, ''])
    results = {}

    # まずHTTPでチェック（公開イベント用）
    histories.each do |h|
      count = check_one(h.site_name, h.event_url)
      if count
        h.update!(registrations: count, registrations_checked_at: Time.current)
        results[h.site_name] = count
      end
    end

    # HTTPで取得できなかったサイトをPlaywrightでチェック
    failed = histories.reject { |h| results.key?(h.site_name) }
    if failed.any?
      pw_results = check_with_playwright(failed)
      pw_results.each do |site_name, count|
        h = failed.find { |fh| fh.site_name == site_name }
        next unless h
        h.update!(registrations: count, registrations_checked_at: Time.current)
        results[site_name] = count
      end
    end

    results
  end

  # Playwright経由で管理画面から参加者数を取得
  def self.check_with_playwright(histories)
    results = {}
    pw_path = find_playwright_path
    return results unless pw_path

    Playwright.create(playwright_cli_executable_path: pw_path) do |playwright|
      browser = playwright.chromium.launch(
        headless: ENV["RAILS_ENV"] == "production",
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
      )

      histories.each do |h|
        begin
          context_opts = {
            userAgent: USER_AGENT + ' Chrome/145.0.0.0 Safari/537.36',
            locale: 'ja-JP',
            viewport: { width: 1280, height: 800 },
          }
          session_file = Rails.root.join('tmp', "#{h.site_name}_session.json").to_s
          context_opts[:storageState] = session_file if File.exist?(session_file)

          context = browser.new_context(**context_opts)
          page = context.new_page
          page.goto(h.event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
          page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

          count = extract_count_from_page(h.site_name, page)
          results[h.site_name] = count if count
        rescue => e
          Rails.logger.warn("[RegistrationChecker][PW] #{h.site_name} error: #{e.message}")
        ensure
          context&.close rescue nil
        end
      end

      browser.close rescue nil
    end
    results
  rescue => e
    Rails.logger.warn("[RegistrationChecker][PW] browser error: #{e.message}")
    results
  end

  def self.extract_count_from_page(site_name, page)
    text = page.evaluate('() => document.body?.innerText || ""') rescue ''
    case site_name
    when 'connpass'
      m = text.match(/参加者\s*(\d+)/) || text.match(/(\d+)\s*\/\s*\d+/)
      m ? m[1].to_i : 0
    when 'peatix'
      m = text.match(/(\d+)\s*人\s*(?:が?参加|申し込み)/) || text.match(/(\d+)\s*tickets?/i)
      m ? m[1].to_i : 0
    when 'kokuchpro'
      m = text.match(/(\d+)\s*人\s*(?:申し込み|参加)/) || text.match(/申込\s*(\d+)/)
      m ? m[1].to_i : 0
    when 'doorkeeper'
      m = text.match(/(\d+)\s*人\s*(?:参加|申し込み)/) || text.match(/(\d+)\s*participants?/i)
      m ? m[1].to_i : 0
    when 'techplay'
      m = text.match(/(\d+)\s*人\s*(?:参加|申し込み)/) || text.match(/interested\s*(\d+)/i)
      m ? m[1].to_i : 0
    when 'street_academy'
      m = text.match(/(\d+)\s*人\s*(?:受けた|参加)/) || text.match(/受講者\s*(\d+)/)
      m ? m[1].to_i : 0
    when 'luma'
      m = text.match(/(\d+)\s*(?:going|registered|attending|guest)/i)
      m ? m[1].to_i : 0
    when 'seminar_biz'
      m = text.match(/(\d+)\s*人/) || text.match(/参加者\s*(\d+)/)
      m ? m[1].to_i : 0
    when 'eventregist'
      m = text.match(/(\d+)\s*人/)
      m ? m[1].to_i : 0
    when 'tunagate'
      m = text.match(/(\d+)\s*人/)
      m ? m[1].to_i : 0
    else
      nil
    end
  end

  def self.find_playwright_path
    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    if File.exist?(local)
      wrapper = '/tmp/playwright-runner.sh'
      File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"\$@\"\n")
      File.chmod(0o755, wrapper)
      return wrapper
    end
    npx = `which npx`.strip
    npx.present? ? "#{npx} playwright" : nil
  end

  def self.check_one(site_name, event_url)
    return nil if event_url.blank?
    case site_name
    when 'peatix'         then check_peatix(event_url)
    when 'connpass'       then check_connpass(event_url)
    when 'kokuchpro'      then check_kokuchpro(event_url)
    when 'doorkeeper'     then check_doorkeeper(event_url)
    when 'techplay'       then check_techplay(event_url)
    when 'tunagate'       then check_generic(event_url, /(\d+)\s*人/)
    when 'street_academy' then check_generic(event_url, /(\d+)\s*人/)
    when 'eventregist'    then check_generic(event_url, /(\d+)\s*人/)
    when 'luma'           then check_luma(event_url)
    when 'seminar_biz'    then check_generic(event_url, /(\d+)\s*人/)
    when 'jimoty'         then check_generic(event_url, /(\d+)\s*人/)
    end
  rescue => e
    Rails.logger.warn("[RegistrationChecker] #{site_name} error: #{e.message}")
    nil
  end

  private

  # Peatix: APIから参加者数を取得（Bearer token使用）
  def self.check_peatix(event_url)
    event_id = event_url[/event\/(\d+)/, 1]
    return nil unless event_id

    # 1. Peatix API（Bearer token）で取得
    conn = ServiceConnection.find_by(service_name: 'peatix')
    if conn&.session_data.present?
      begin
        session = JSON.parse(conn.session_data)
        # localStorage から peatix_frontend_access_token を取得
        token = nil
        (session['origins'] || []).each do |origin|
          (origin['localStorage'] || []).each do |item|
            token = item['value'].to_s if item['name'] == 'peatix_frontend_access_token'
          end
        end

        if token
          uri = URI("https://peatix-api.com/v4/events/#{event_id}/orders")
          req = Net::HTTP::Get.new(uri)
          req['Authorization'] = "Bearer #{token}"
          req['Accept'] = 'application/json'
          req['Origin'] = 'https://peatix.com'
          req['Referer'] = 'https://peatix.com/'
          req['X-Requested-With'] = 'XMLHttpRequest'
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
          if res.is_a?(Net::HTTPSuccess)
            data = JSON.parse(res.body) rescue {}
            total = data.dig('paginationInfo', 'totalItems')
            return total.to_i if total
          end
        end
      rescue => e
        Rails.logger.warn("[RegistrationChecker] peatix API error: #{e.message}")
      end
    end

    # 2. 公開ページHTMLフォールバック
    html = fetch_html("https://peatix.com/event/#{event_id}")
    return nil unless html
    doc = Nokogiri::HTML(html)
    text = doc.text
    if (m = text.match(/(\d+)\s*人\s*(?:が?参加|申し込み|attending)/))
      return m[1].to_i
    end
    doc.css('script[type="application/ld+json"]').each do |script|
      data = JSON.parse(script.text) rescue next
      return data['attendeeCount'].to_i if data['attendeeCount']
    end
    0
  end

  # connpass: HTMLスクレイピングで参加者数を取得
  def self.check_connpass(event_url)
    event_id = event_url[/event\/(\d+)/, 1]
    return nil unless event_id

    # 公開ページのHTMLから参加者数を抽出
    html = fetch_html("https://connpass.com/event/#{event_id}/")
    return nil unless html

    doc = Nokogiri::HTML(html)

    # "参加者 X人" パターン
    text = doc.text
    if (m = text.match(/参加者\s*(\d+)/))
      return m[1].to_i
    end
    # "X / Y人" パターン（定員表示）
    if (m = text.match(/(\d+)\s*\/\s*\d+\s*人/))
      return m[1].to_i
    end
    0
  end

  # こくチーズ: HTMLから参加者数を取得
  def self.check_kokuchpro(event_url)
    # admin URL → public URLに変換
    public_url = event_url.gsub('/admin/', '/event/')
    html = fetch_html(public_url)
    return nil unless html
    if (m = html.match(/(\d+)\s*人\s*(?:申し込み|参加|残り)/))
      return m[1].to_i
    end
    0
  end

  # Doorkeeper: HTMLから参加者数を取得
  def self.check_doorkeeper(event_url)
    # Doorkeeper API v2で参加者数を取得
    if (m = event_url.match(%r{/events/(\d+)}))
      event_id = m[1]
      # Doorkeeper公開API: /events/:id
      begin
        uri = URI("https://api.doorkeeper.jp/events/#{event_id}")
        req = Net::HTTP::Get.new(uri)
        req['Accept'] = 'application/json'
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
        if res.is_a?(Net::HTTPSuccess)
          data = JSON.parse(res.body) rescue {}
          event = data['event'] || data
          participants = event['participants'] || event['ticket_count'] || event['waitlisted']
          return participants.to_i if participants
        end
      rescue => e
        Rails.logger.warn("[RegistrationChecker] doorkeeper API error: #{e.message}")
      end
    end

    # フォールバック: 公開ページHTMLから取得
    public_url = event_url
    if event_url.include?('manage.doorkeeper.jp')
      if (m2 = event_url.match(%r{manage\.doorkeeper\.jp/groups/([^/]+)/events/(\d+)}))
        public_url = "https://#{m2[1]}.doorkeeper.jp/events/#{m2[2]}"
      end
    end
    html = fetch_html(public_url)
    return 0 unless html
    text = Nokogiri::HTML(html).text
    # 「申し込み数: X」パターン（定員ではなく申し込み数を取得）
    if (m3 = text.match(/申し込み数[：:]\s*(\d+)/))
      return m3[1].to_i
    end
    # 「X / Y」パターン（参加者/定員）
    if (m4 = text.match(/(\d+)\s*\/\s*\d+\s*人/))
      return m4[1].to_i
    end
    0
  end

  # TechPlay: セッション Cookie で owner 管理ページから参加者数を取得
  def self.check_techplay(event_url)
    # event_url: https://owner.techplay.jp/event/994580/edit
    event_id = event_url[/event\/(\d+)/, 1]
    return nil unless event_id

    # 1. セッション Cookie で owner ページを取得
    conn = ServiceConnection.find_by(service_name: 'techplay')
    if conn&.session_data.present?
      html = fetch_techplay_with_session(conn.session_data, "https://owner.techplay.jp/event/#{event_id}/edit")
      if html && (m = html.match(/data-page="([^"]+)"/))
        begin
          page_data = JSON.parse(CGI.unescapeHTML(m[1]))
          entered = page_data.dig('props', 'event', 'entered')
          return entered.to_i if entered
        rescue JSON::ParserError; end
      end
    end

    # 2. フォールバック: 公開ページ（ローカル環境用）
    public_url = "https://techplay.jp/event/#{event_id}"
    html = fetch_html(public_url)
    return nil unless html
    if (m = html.match(/data-page="([^"]+)"/))
      begin
        page_data = JSON.parse(CGI.unescapeHTML(m[1]))
        entered = page_data.dig('props', 'event', 'entered')
        return entered.to_i if entered
      rescue JSON::ParserError; end
    end
    if (m2 = html.match(/(\d+)\s*人\s*(?:参加|申し込み|interested)/))
      return m2[1].to_i
    end
    0
  end

  def self.fetch_techplay_with_session(session_json, url)
    session = JSON.parse(session_json) rescue {}
    cookies = (session['cookies'] || []).map { |c| "#{c['name']}=#{c['value']}" }.join('; ')
    return nil if cookies.blank?

    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    req['Cookie'] = cookies
    req['Accept'] = 'text/html'
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) { |h| h.request(req) }

    # リダイレクト追跡（最大2回）
    2.times do
      break unless res.is_a?(Net::HTTPRedirection)
      uri = URI(res['location'])
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      req['Cookie'] = cookies
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) { |h| h.request(req) }
    end
    res.body if res.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.warn("[RegistrationChecker] TechPlay session fetch error: #{e.message}")
    nil
  end

  # Luma: 管理URLを公開URLに変換してチェック
  def self.check_luma(event_url)
    # luma.com/event/manage/evt-XXX → lu.ma/evt-XXX
    public_url = event_url
    if (m = event_url.match(/(evt-\w+)/))
      public_url = "https://lu.ma/#{m[1]}"
    end
    html = fetch_html(public_url)
    return nil unless html
    if (m = html.match(/(\d+)\s*(?:going|registered|attending|guest)/i))
      return m[1].to_i
    end
    0
  end

  # 汎用: HTMLから正規表現で抽出
  def self.check_generic(event_url, pattern)
    html = fetch_html(event_url)
    return nil unless html
    if (m = html.match(pattern))
      return m[1].to_i
    end
    0
  end

  def self.fetch_html(url, depth = 0)
    return nil if depth > 3
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 15
    http.open_timeout = 10
    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = USER_AGENT
    req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    req['Accept-Language'] = 'ja,en-US;q=0.9,en;q=0.8'
    req['Cache-Control'] = 'no-cache'
    res = http.request(req)
    if res.is_a?(Net::HTTPRedirection) && res['location']
      loc = res['location']
      loc = "#{uri.scheme}://#{uri.host}#{loc}" if loc.start_with?('/')
      return fetch_html(loc, depth + 1)
    end
    if res.is_a?(Net::HTTPSuccess)
      body = res.body
      body.force_encoding('UTF-8') unless body.encoding == Encoding::UTF_8
      body.encode!('UTF-8', invalid: :replace, undef: :replace, replace: '')
      body
    end
  rescue => e
    Rails.logger.warn("[RegistrationChecker] fetch error #{url}: #{e.message}")
    nil
  end
end
