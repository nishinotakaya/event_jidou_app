require 'playwright'

class OnclassCommunityScanner
  BASE_URL = 'https://manager.the-online-class.com'.freeze
  # https://あり・なし両方にマッチ
  GITHUB_URL_PATTERN = %r{(?:https?://)?github\.com/[^\s<>"'\)]+}

  # 対応済みと判定するフレーズ（自分の返信に含まれていたらスキップ）
  RESOLVED_PHRASES = [
    'お進みください',
    '進めてください',
    '問題なさそう',
    '問題ありません',
    '修正ありがとう',
    'ありがとうございます',
    'LGTM',
    'lgtm',
    '良さそう',
    'いい感じ',
    '大丈夫です',
    'OKです',
    'okです',
    '確認しました',
    'レビュー済み',
    'マージして',
  ].freeze

  def initialize(logger: nil)
    @logger = logger || Rails.logger
  end

  # メインエントリポイント: メンションタブから未対応のGitHub URLを検出
  # Returns: [{ url:, author:, channel:, message:, images:, post_id: }]
  def scan
    results = []
    reviewed_urls = GithubReview.pluck(:github_url).to_set

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: true)
      page = browser.new_page

      begin
        ensure_login(page)
        navigate_to_community(page)

        # メンションタブをクリック
        open_mention_tab(page)

        # メンション一覧を取得
        mentions = extract_mentions(page)
        log "📡 #{mentions.length}件のメンションを検出"

        mentions.each do |mention|
          full_text = mention[:text].to_s
          next if full_text.strip.empty?

          # GitHub URLを検出
          urls = full_text.scan(GITHUB_URL_PATTERN).uniq
          next if urls.empty?

          urls.each do |url|
            clean_url = normalize_github_url(url)
            next if reviewed_urls.include?(clean_url)

            # URL前後200文字の文脈で対応済み判定（ページ全体ではなく局所的に判定）
            url_pos = full_text.index(url)
            if url_pos
              context_start = [url_pos - 300, 0].max
              context_end = [url_pos + url.length + 300, full_text.length].min
              context = full_text[context_start..context_end]
              if resolved_context?(context)
                log "  ⏭️ 対応済みスキップ: #{clean_url}"
                next
              end
            end

            results << {
              url: clean_url,
              author: mention[:author],
              channel: mention[:channel],
              message: full_text[([url_pos.to_i - 200, 0].max)..([url_pos.to_i + url.length + 500, full_text.length].min)],
              images: mention[:images],
              post_id: mention[:post_id],
            }
            reviewed_urls << clean_url
            log "  🆕 未対応GitHub URL検出: #{clean_url}"
          end
        end

        log "📋 結果: #{results.length}件の未対応GitHub URL"
      ensure
        browser.close
      end
    end

    results
  end

  private

  def log(msg)
    @logger.info(msg)
  end

  def ensure_login(page)
    creds = ServiceConnection.credentials_for('onclass')
    email = creds[:email].presence || 'takaya314boxing@gmail.com'
    password = creds[:password].presence || 'takaya314'

    page.goto("#{BASE_URL}/sign_in", timeout: 30_000, waitUntil: 'load')
    page.wait_for_timeout(3000)
    return log('✅ オンクラスログイン済み') unless page.url.include?('sign_in')

    page.fill('input[name="email"]', email)
    page.fill('input[name="password"]', password)
    page.locator('button:has-text("ログインする")').click
    page.wait_for_timeout(5000)

    raise 'オンクラスログイン失敗' if page.url.include?('sign_in')
    log('✅ オンクラスログイン完了')
  end

  def navigate_to_community(page)
    page.goto("#{BASE_URL}/community", timeout: 30_000, waitUntil: 'load')
    page.wait_for_timeout(5000)
  end

  # サイドバーの「メンション」タブを開く
  def open_mention_tab(page)
    page.evaluate(<<~JS)
      (() => {
        const items = [...document.querySelectorAll('.v-list-item, .v-tab, [role="tab"], button, a')];
        const target = items.find(el => {
          const text = el.textContent.trim();
          return text === 'メンション' || text.includes('メンション');
        });
        if (target) {
          target.scrollIntoView({ block: 'center', behavior: 'instant' });
          target.click();
          return true;
        }
        return false;
      })()
    JS
    page.wait_for_timeout(4000)
    log('📌 メンションタブを開きました')
  end

  # メンション一覧を抽出（サロゲートペア問題を回避するためページ全体テキストから抽出）
  def extract_mentions(page)
    # スクロールして全メンションを読み込む（最大3回）
    3.times do
      page.evaluate('(() => { const el = document.querySelector("main, .v-main"); if (el) el.scrollTop = el.scrollHeight; })()')
      page.wait_for_timeout(2000)
    end

    # ページ全体のテキストを取得（サロゲートペアを除去してJSONエラー回避）
    full_text = page.evaluate('document.body.innerText.replace(/[\\ud800-\\udfff]/g, "").substring(0, 100000)')

    # 画像URLを取得
    images = page.evaluate('(() => { try { return [...document.querySelectorAll("main img, .v-main img")].map(img => img.src).filter(s => s && !s.includes("avatar")); } catch(e) { return []; } })()')

    # テキストをメンション単位に分割（投稿者名パターンで区切る）
    # メンションタブでは各メンションが順番に並ぶので、全体テキストを1つのメンションとして扱う
    [{
      text: full_text.to_s,
      author: '',
      channel: 'メンション',
      images: images || [],
      post_id: "mention_page_#{Time.now.to_i}",
      replies: [],
    }]
  end

  # URL前後の文脈から対応済みかどうかを判定
  def resolved_context?(context)
    RESOLVED_PHRASES.any? { |phrase| context.include?(phrase) }
  end

  def normalize_github_url(url)
    clean = url.sub(/[.,;:!?\)\]]+$/, '').strip
    # https:// がなければ付与
    clean = "https://#{clean}" unless clean.start_with?('http')
    clean
  end
end
