require 'playwright'

class EventSearchService
  # 各ポータルサイトのマイページ/管理画面でイベント名を検索し、マッチするURLを返す
  SITE_CONFIGS = {
    'kokuchpro' => {
      url: 'https://www.kokuchpro.com/mypage/event/',
      login_url: 'https://www.kokuchpro.com/login/',
      selector: 'a',
      link_pattern: %r{kokuchpro\.com/.+/ev/},
    },
    'connpass' => {
      url: 'https://connpass.com/editmanage/',
      selector: '.event_list a, .group_event_inner a, a[href*="/event/"]',
      link_pattern: %r{connpass\.com/event/\d+},
    },
    'peatix' => {
      url: 'https://peatix.com/dashboard',
      selector: 'a[href*="/event/"]',
      link_pattern: %r{peatix\.com/event/\d+},
    },
    'techplay' => {
      url: 'https://owner.techplay.jp/dashboard',
      selector: 'a',
      link_pattern: %r{techplay\.jp/event/\d+},
    },
    'tunagate' => {
      url: 'https://tunagate.com/mypage',
      selector: 'a',
      link_pattern: %r{tunagate\.com/circle/.+/event/},
    },
    'doorkeeper' => {
      url: 'https://manage.doorkeeper.jp/groups',
      selector: 'a',
      link_pattern: %r{doorkeeper\.jp/.+/events/\d+},
    },
  }.freeze

  def initialize(logger: nil)
    @logger = logger || Rails.logger
  end

  # 指定したitem_idのイベント名で各ポータルサイトを検索し、PostingHistoryを作成
  def search_and_sync(item_id)
    item = Item.find(item_id)
    event_name = item.name
    results = []

    # 接続済みサービスのみ対象
    connected = ServiceConnection.where(status: 'connected').pluck(:service_name).to_set

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: true)
      page = browser.new_page(viewport: { width: 1280, height: 800 })

      SITE_CONFIGS.each do |site_name, config|
        next unless connected.include?(site_name)
        # 既に投稿履歴がある場合はスキップ
        next if PostingHistory.exists?(item_id: item_id, site_name: site_name)

        begin
          log "🔍 #{site_name}: 「#{event_name}」を検索中..."
          ensure_login(page, site_name)
          found = search_on_site(page, config, event_name, site_name)

          if found
            PostingHistory.create!(
              item_id: item_id,
              site_name: site_name,
              status: 'success',
              event_url: found[:url],
              published: true,
              posted_at: Time.current,
            )
            results << { site: site_name, url: found[:url], status: 'found' }
            log "  ✅ 発見: #{found[:url]}"
          else
            log "  ⏭️ 見つかりませんでした"
          end
        rescue => e
          log "  ❌ #{site_name}: #{e.message}"
        end
      end

      browser.close
    end

    results
  end

  private

  def log(msg)
    @logger.info(msg)
  end

  def ensure_login(page, site_name)
    creds = ServiceConnection.credentials_for(site_name)
    return unless creds[:email].present?

    config = SITE_CONFIGS[site_name]
    page.goto(config[:url], timeout: 30_000, waitUntil: 'domcontentloaded')
    page.wait_for_timeout(3000)

    # ログインページにリダイレクトされた場合
    if page.url.include?('login') || page.url.include?('sign_in') || page.url.include?('signin')
      login_url = config[:login_url] || page.url
      page.goto(login_url, timeout: 30_000, waitUntil: 'domcontentloaded')
      page.wait_for_timeout(2000)

      # メール/パスワード入力（汎用パターン）
      email_input = page.locator('input[type="email"], input[name="email"], input[name*="mail"], input[id*="email"]').first
      pass_input = page.locator('input[type="password"]').first

      if email_input && pass_input
        email_input.fill(creds[:email])
        pass_input.fill(creds[:password])
        submit = page.locator('button[type="submit"], input[type="submit"], button:has-text("ログイン"), button:has-text("Login")').first
        submit.click if submit
        page.wait_for_timeout(5000)
      end
    end
  end

  # サイトのマイページからイベント名で検索
  def search_on_site(page, config, event_name, site_name)
    page.goto(config[:url], timeout: 30_000, waitUntil: 'domcontentloaded')
    page.wait_for_timeout(3000)

    # ページ内のイベント名を部分一致で検索
    # 名前の主要部分（記号・空白を正規化）で検索
    search_keywords = extract_keywords(event_name)

    found = page.evaluate(<<~JS, arg: { keywords: search_keywords, linkPattern: config[:link_pattern].source })
      (({ keywords, linkPattern }) => {
        const pattern = new RegExp(linkPattern);
        const links = document.querySelectorAll('a');
        for (const link of links) {
          const text = link.textContent.trim();
          const href = link.href || '';
          // リンクテキストまたはその親要素のテキストにキーワードが含まれるか
          const parentText = link.closest('li, tr, div, article')?.textContent?.trim() || text;

          const matched = keywords.every(kw => parentText.includes(kw));
          if (matched && pattern.test(href)) {
            return { url: href, text: text.substring(0, 100) };
          }
        }

        // リンクが見つからない場合、テキストノードで検索してから最も近いリンクを探す
        const allText = document.body.innerText;
        if (keywords.every(kw => allText.includes(kw))) {
          // ページ内にキーワードが存在するが、リンクと紐付かない
          return null;
        }
        return null;
      })
    JS

    found
  end

  # イベント名からキーワードを抽出（部分一致検索用）
  def extract_keywords(name)
    # 記号を除去してスペースで分割、短すぎる単語は除外
    cleaned = name.gsub(/[｜|【】「」（）()・\-—]/, ' ')
    words = cleaned.split(/\s+/).reject { |w| w.length < 2 }
    # 最大3キーワードに絞る（長い順）
    words.sort_by { |w| -w.length }.first(3)
  end
end
