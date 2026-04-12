require 'playwright'
require 'shellwords'

# 各ポータルサイトの管理画面から参加者（名前・メールアドレス）を取得
class ParticipantChecker
  SITE_CONFIGS = {
    'connpass' => {
      participants_url: ->(url) {
        event_id = url[/event\/(\d+)/, 1]
        event_id ? "https://connpass.com/event/#{event_id}/participation/" : nil
      },
    },
    'peatix' => {
      participants_url: ->(url) {
        event_id = url[/event\/(\d+)/, 1]
        event_id ? "https://peatix.com/event/#{event_id}/orders" : nil
      },
    },
    'kokuchpro' => {
      participants_url: ->(url) { url }, # 管理画面に直接アクセス
    },
    'doorkeeper' => {
      participants_url: ->(url) {
        url.sub(/\/?$/, '/attendees')
      },
    },
    'techplay' => {
      participants_url: ->(url) {
        base = url.sub(/\/edit\/?$/, '')
        "#{base}/attendee"
      },
    },
    'luma' => {
      participants_url: ->(url) {
        url.sub(/\/?$/, '/guests')
      },
    },
    'tunagate' => {
      participants_url: ->(url) { url },
    },
    'street_academy' => {
      participants_url: ->(url) { url },
    },
    'eventregist' => {
      participants_url: ->(url) { url },
    },
    'seminar_biz' => {
      participants_url: ->(url) { url },
    },
  }.freeze

  def self.check_all(item_id)
    histories = PostingHistory.where(item_id: item_id, status: 'success')
      .where.not(event_url: [nil, '', 'about:blank'])

    return {} if histories.empty?

    results = {}

    # Peatix は API で取得（Playwright 不要）
    peatix_history = histories.find { |h| h.site_name == 'peatix' }
    if peatix_history
      participants = extract_peatix_participants_api(peatix_history.event_url)
      results['peatix'] = {
        site_label: 'Peatix',
        event_url: peatix_history.event_url,
        participants: participants,
      }
    end

    pw_path = find_playwright_path
    return results unless pw_path

    Playwright.create(playwright_cli_executable_path: pw_path) do |playwright|
      browser = playwright.chromium.launch(
        headless: ENV["RAILS_ENV"] == "production",
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
      )

      histories.each do |history|
        next if history.site_name == 'peatix' # API で取得済み
        config = SITE_CONFIGS[history.site_name]
        next unless config

        begin
          context_opts = {
            userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
            locale: 'ja-JP',
            viewport: { width: 1280, height: 800 },
          }
          session_file = Rails.root.join('tmp', "#{history.site_name}_session.json").to_s
          context_opts[:storageState] = session_file if File.exist?(session_file)

          context = browser.new_context(**context_opts)
          page = context.new_page

          # ログイン
          login_for(history.site_name, page)

          # 参加者ページへ
          participants_url = config[:participants_url].call(history.event_url)
          next unless participants_url

          page.goto(participants_url, waitUntil: 'domcontentloaded', timeout: 30_000)
          page.wait_for_timeout(3000)

          # 参加者を抽出
          participants = extract_participants(history.site_name, page)
          results[history.site_name] = {
            site_label: PostingHistory::SITE_LABELS[history.site_name] || history.site_name,
            event_url: history.event_url,
            participants: participants,
          }
        rescue => e
          Rails.logger.warn("[ParticipantChecker] #{history.site_name} error: #{e.message}")
          results[history.site_name] = {
            site_label: PostingHistory::SITE_LABELS[history.site_name] || history.site_name,
            event_url: history.event_url,
            participants: [],
            error: e.message,
          }
        ensure
          context&.close rescue nil
        end
      end

      browser.close rescue nil
    end

    results
  end

  private

  def self.login_for(site_name, page)
    case site_name
    when 'connpass'
      Posting::ConnpassService.new.send(:ensure_login, page)
    when 'peatix'
      # Peatixはセッションベースで参加者ページにアクセス
      page.goto('https://peatix.com/', waitUntil: 'domcontentloaded', timeout: 15_000)
      page.wait_for_timeout(1000)
    when 'kokuchpro'
      page.goto('https://www.kokuchpro.com/auth/login/', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(1000)
      if page.url.include?('login')
        creds = ServiceConnection.credentials_for('kokuchpro')
        page.fill('#LoginFormEmail', creds[:email])
        page.fill('#LoginFormPassword', creds[:password])
        page.click('#UserLoginForm button[type="submit"]') rescue nil
        page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
      end
    when 'doorkeeper'
      Posting::DoorkeeperService.new.send(:ensure_login, page) rescue nil
    when 'techplay'
      Posting::TechplayService.new.send(:ensure_login, page) rescue nil
    when 'luma'
      Posting::LumaService.new.send(:ensure_login, page) rescue nil
    when 'tunagate'
      Posting::TunagateService.new.send(:ensure_login, page) rescue nil
    when 'street_academy'
      Posting::StreetAcademyService.new.send(:ensure_login, page) rescue nil
    when 'eventregist'
      Posting::EventregistService.new.send(:ensure_login, page) rescue nil
    when 'seminar_biz'
      Posting::SeminarBizService.new.send(:ensure_login, page) rescue nil
    end
  end

  def self.extract_participants(site_name, page)
    # 汎用抽出: ページ内のテーブル・リストから名前とメールを抽出
    participants = page.evaluate(<<~JS)
      (() => {
        const results = [];
        const emailRegex = /[\\w.+-]+@[\\w.-]+\\.\\w+/;

        // テーブルからの抽出
        const tables = document.querySelectorAll('table');
        tables.forEach(table => {
          const headers = [...table.querySelectorAll('th')].map(h => h.textContent.trim().toLowerCase());
          const nameCol = headers.findIndex(h => /名前|name|氏名|ユーザー|表示名|ニックネーム/.test(h));
          const emailCol = headers.findIndex(h => /メール|email|mail|e-mail|アドレス/.test(h));

          table.querySelectorAll('tbody tr, tr').forEach(tr => {
            const cells = [...tr.querySelectorAll('td')];
            if (cells.length === 0) return;

            let name = '';
            let email = '';

            if (nameCol >= 0 && cells[nameCol]) name = cells[nameCol].textContent.trim();
            if (emailCol >= 0 && cells[emailCol]) email = cells[emailCol].textContent.trim();

            // カラムが特定できない場合: セルを全探索
            if (!name && !email) {
              cells.forEach(cell => {
                const text = cell.textContent.trim();
                if (!email && emailRegex.test(text)) {
                  email = text.match(emailRegex)[0];
                } else if (!name && text.length > 0 && text.length < 50 && !/^\\d+$/.test(text) && !/^[¥$€]/.test(text)) {
                  name = text;
                }
              });
            }

            if (name || email) results.push({ name, email });
          });
        });

        // テーブルで見つからない場合: リスト要素から
        if (results.length === 0) {
          // カード形式の参加者（Luma等）
          const cards = document.querySelectorAll('[class*="guest"], [class*="attendee"], [class*="participant"], [class*="member"]');
          cards.forEach(card => {
            const text = card.textContent.trim();
            const emailMatch = text.match(emailRegex);
            const lines = text.split('\\n').map(l => l.trim()).filter(l => l.length > 0 && l.length < 80);
            const name = lines.find(l => !emailRegex.test(l) && !/^\\d/.test(l) && l.length < 40) || '';
            results.push({ name, email: emailMatch ? emailMatch[0] : '' });
          });
        }

        // ページ全体からメールアドレスを探す（最終手段）
        if (results.length === 0) {
          const bodyText = document.body.innerText;
          const allEmails = [...new Set(bodyText.match(/[\\w.+-]+@[\\w.-]+\\.\\w+/g) || [])];
          allEmails.forEach(email => {
            // メールアドレスの前の行を名前として推定
            const idx = bodyText.indexOf(email);
            const before = bodyText.substring(Math.max(0, idx - 100), idx);
            const lines = before.split('\\n').map(l => l.trim()).filter(l => l.length > 0 && l.length < 40);
            const name = lines[lines.length - 1] || '';
            results.push({ name, email });
          });
        }

        // 重複除去
        const seen = new Set();
        return results.filter(p => {
          const key = (p.email || p.name).toLowerCase();
          if (!key || seen.has(key)) return false;
          seen.add(key);
          return true;
        });
      })()
    JS

    # サイト固有の後処理
    case site_name
    when 'connpass'
      # connpassは管理ページからユーザー名取得（メールは非公開の場合あり）
      participants = extract_connpass_participants(page) if participants.empty?
    when 'peatix'
      participants = extract_peatix_participants(page) if participants.empty?
    end

    participants || []
  end

  # connpass固有: editmanageの参加者リスト
  def self.extract_connpass_participants(page)
    page.evaluate(<<~JS)
      (() => {
        const results = [];
        // connpassの参加者ブロック
        const items = document.querySelectorAll('.participation_table_area .display_name, .applicant_area .display_name, .user_info .display_name');
        items.forEach(el => {
          const name = el.textContent.trim();
          if (name) results.push({ name, email: '' });
        });
        // フォールバック: リンクテキストから
        if (results.length === 0) {
          document.querySelectorAll('a[href*="/user/"]').forEach(a => {
            const name = a.textContent.trim();
            if (name && name.length < 40 && !/connpass|イベント/.test(name)) {
              results.push({ name, email: '' });
            }
          });
        }
        return results;
      })()
    JS
  end

  # Peatix: API経由で参加者名を取得（Playwright不要）
  def self.extract_peatix_participants_api(event_url)
    event_id = event_url[/event\/(\d+)/, 1]
    return [] unless event_id

    conn = ServiceConnection.find_by(service_name: 'peatix')
    return [] unless conn&.session_data.present?

    session = JSON.parse(conn.session_data) rescue {}
    token = nil
    (session['origins'] || []).each do |origin|
      (origin['localStorage'] || []).each do |item|
        token = item['value'].to_s if item['name'] == 'peatix_frontend_access_token'
      end
    end
    return [] unless token.present?

    results = []
    page_num = 1
    loop do
      uri = URI("https://peatix-api.com/v4/events/#{event_id}/orders?page=#{page_num}")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{token}"
      req['Accept'] = 'application/json'
      req['Origin'] = 'https://peatix.com'
      req['X-Requested-With'] = 'XMLHttpRequest'
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
      break unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body) rescue {}
      orders = data['data'] || []
      break if orders.empty?

      orders.each do |order|
        buyer_name = order.dig('buyer', 'name').to_s
        owners = order['owners'] || []
        attendances = order['attendances'] || []

        # owners（実際の参加者）を優先
        if owners.any?
          owners.each { |o| results << { 'name' => o['name'].to_s, 'email' => '' } }
        elsif buyer_name.present?
          results << { 'name' => buyer_name, 'email' => '' }
        end
      end

      total_pages = data.dig('paginationInfo', 'totalPages') || 1
      break if page_num >= total_pages
      page_num += 1
    end

    results.uniq { |r| r['name'] }
  rescue => e
    Rails.logger.warn("[ParticipantChecker] peatix API error: #{e.message}")
    []
  end

  # Peatix固有フォールバック（Playwright版）
  def self.extract_peatix_participants(page)
    page.evaluate(<<~JS)
      (() => {
        const results = [];
        const rows = document.querySelectorAll('.order-row, [class*="order"], tr');
        rows.forEach(row => {
          const text = row.textContent;
          const emailMatch = text.match(/[\\w.+-]+@[\\w.-]+\\.\\w+/);
          const nameEl = row.querySelector('.name, [class*="name"], td:first-child');
          const name = nameEl ? nameEl.textContent.trim() : '';
          if (name || emailMatch) {
            results.push({ name, email: emailMatch ? emailMatch[0] : '' });
          }
        });
        return results;
      })()
    JS
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
end
