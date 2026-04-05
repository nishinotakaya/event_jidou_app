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
        headless: false,
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
      unless File.exist?(wrapper)
        File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
        File.chmod(0o755, wrapper)
      end
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

  # Peatix: 公開ページから参加者数を取得
  def self.check_peatix(event_url)
    # event_url: https://peatix.com/event/4940762
    event_id = event_url[/event\/(\d+)/, 1]
    return nil unless event_id

    # 公開ページのHTMLから参加者数を抽出
    html = fetch_html("https://peatix.com/event/#{event_id}")
    return nil unless html

    doc = Nokogiri::HTML(html)

    # Peatixは複数のフォーマットで参加者数を表示
    # 1. "X人参加" パターン
    text = doc.text
    if (m = text.match(/(\d+)\s*人\s*(?:が?参加|申し込み|attending)/))
      return m[1].to_i
    end

    # 2. JSON-LD内のattendee数
    doc.css('script[type="application/ld+json"]').each do |script|
      begin
        data = JSON.parse(script.text)
        if data['attendeeCount']
          return data['attendeeCount'].to_i
        end
      rescue
      end
    end

    # 3. list_sales ページを試す（認証が必要かもしれないが公開イベントならOK）
    sales_html = fetch_html("https://peatix.com/event/#{event_id}/list_sales")
    if sales_html
      if (m = sales_html.match(/(\d+)\s*(?:件|枚|人|tickets?)/i))
        return m[1].to_i
      end
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
    # 管理URL → 公開URLに変換
    # manage.doorkeeper.jp/groups/XXX/events/123 → XXX.doorkeeper.jp/events/123
    public_url = event_url
    if event_url.include?('manage.doorkeeper.jp')
      if (m = event_url.match(%r{manage\.doorkeeper\.jp/groups/([^/]+)/events/(\d+)}))
        public_url = "https://#{m[1]}.doorkeeper.jp/events/#{m[2]}"
      end
    end
    html = fetch_html(public_url)
    return nil unless html
    if (m = html.match(/(\d+)\s*人\s*(?:参加|申し込み)/))
      return m[1].to_i
    end
    0
  end

  # TechPlay: HTMLから参加者数を取得
  def self.check_techplay(event_url)
    # owner.techplay.jp/event/XXX/edit → techplay.jp/event/XXX
    public_url = event_url
      .sub('owner.techplay.jp', 'techplay.jp')
      .sub(%r{/edit/?$}, '')
    html = fetch_html(public_url)
    return nil unless html
    if (m = html.match(/(\d+)\s*人\s*(?:参加|申し込み|interested)/))
      return m[1].to_i
    end
    0
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
    res.is_a?(Net::HTTPSuccess) ? res.body : nil
  rescue => e
    Rails.logger.warn("[RegistrationChecker] fetch error #{url}: #{e.message}")
    nil
  end
end
