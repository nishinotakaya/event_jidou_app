module Posting
  # Threads (threads.net / Meta) 投稿サービス。
  # Threads は Instagram アカウントでログインする Meta 製 SNS。
  # Instagram と異なりテキストのみの投稿が可能（画像は任意）。
  #
  # 認証は ServiceConnection.credentials_for('threads')（既定で INSTAGRAM_EMAIL/PASSWORD に
  # フォールバック）を使う。post_job.rb の deferred_sites（SNS）経路から呼ばれ、
  # 選ばれたら即投稿（下書き概念なし）。
  class ThreadsService < BaseService
    HOME_URL  = 'https://www.threads.net/'
    LOGIN_URL = 'https://www.threads.net/login/'
    TEXT_LIMIT = 500

    private

    def execute(page, content, ef)
      ensure_login(page)

      title     = extract_title(ef, content, 80)
      event_url = find_event_url(ef)
      text      = build_post(title, content, event_url, ef)

      log('[Threads] 投稿作成中...')
      page.goto(HOME_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      open_composer(page)

      # テキスト入力（contenteditable）
      editor = page.locator('div[role="dialog"] div[contenteditable="true"], div[contenteditable="true"][role="textbox"]').first
      raise '[Threads] 投稿入力欄が見つかりません' unless (editor.visible?(timeout: 8000) rescue false)
      editor.click
      page.wait_for_timeout(500)
      page.keyboard.type(text, delay: 5)
      page.wait_for_timeout(1000)
      log("[Threads] 本文入力完了 (#{text.length}文字)")

      # 画像が指定されていれば添付（任意）
      image_path = ef['imagePath'].to_s
      if image_path.present? && File.exist?(image_path)
        begin
          file_input = page.locator('div[role="dialog"] input[type="file"], input[type="file"]').first
          file_input.set_input_files(image_path)
          page.wait_for_timeout(5000)
          log('[Threads] 画像添付完了')
        rescue => e
          log("[Threads] ⚠️ 画像添付スキップ: #{e.message}")
        end
      end

      # 「投稿」ボタン
      page.wait_for_timeout(1500)
      posted = page.evaluate(<<~'JS')
        (() => {
          const scope = document.querySelector('div[role="dialog"]') || document;
          const all = [...scope.querySelectorAll('button, div[role="button"]')];
          const btn = all.reverse().find(b => /^投稿(する)?$|^Post$/.test(b.textContent?.trim()) && b.getAttribute('aria-disabled') !== 'true');
          if (btn) { btn.click(); return true; }
          return false;
        })()
      JS
      raise '[Threads] 投稿ボタンが見つかりません' unless posted

      page.wait_for_timeout(8000)
      @published = true
      log('[Threads] ✅ 投稿完了')
    end

    # 「新規スレッド」コンポーザを開く（複数の UI パターンに対応）
    def open_composer(page)
      opened = page.evaluate(<<~'JS')
        (() => {
          // フィード上部の「新規スレッドを作成」入力 or サイドバー/ヘッダの作成ボタン
          const byLabel = document.querySelector(
            'svg[aria-label="作成"], svg[aria-label="新規スレッド"], svg[aria-label="Create"], svg[aria-label="New thread"], [aria-label="投稿"], [aria-label="Post"]'
          );
          if (byLabel) {
            const t = byLabel.closest('a') || byLabel.closest('div[role="button"]') || byLabel.closest('button') || byLabel.parentElement;
            if (t) { t.click(); return 'label'; }
          }
          // テキストで探す（「新規スレッド」「Start a thread...」）
          const cands = [...document.querySelectorAll('div[role="button"], button, a, span')];
          const hit = cands.find(el => /新規スレッド|スレッドを作成|Start a thread|新しいスレッド/.test(el.textContent?.trim()));
          if (hit) { hit.click(); return 'text'; }
          return false;
        })()
      JS
      raise '[Threads] 投稿作成ボタンが見つかりません' unless opened
      page.wait_for_timeout(3000)
      log("[Threads] コンポーザを開きました (#{opened})")
    end

    def ensure_login(page)
      page.goto(HOME_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      # 通知許可等の「後で」をスキップ
      later_btn = page.locator('button:has-text("後で"), button:has-text("Not Now"), button:has-text("Later")').first
      later_btn.click if (later_btn.visible?(timeout: 2000) rescue false)
      page.wait_for_timeout(1000)

      # ログイン済み判定（ログインページに飛ばされていなければ OK）
      unless page.url.include?('login')
        composer_indicator = page.locator('svg[aria-label="作成"], svg[aria-label="Create"], div[role="button"]:has-text("新規スレッド")').first
        if (composer_indicator.visible?(timeout: 5000) rescue false)
          log('[Threads] ✅ ログイン済み')
          return
        end
      end

      log('[Threads] ログイン中...')
      creds = ServiceConnection.credentials_for('threads')
      if creds[:email].blank?
        raise '[Threads] ログイン情報がありません。接続管理画面から Instagram(Threads) の認証を設定してください。'
      end

      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      # 「Instagram でログイン」導線があれば踏む
      ig_login = page.locator('a:has-text("Instagram"), div[role="button"]:has-text("Instagram"), button:has-text("Instagram")').first
      if (ig_login.visible?(timeout: 3000) rescue false)
        ig_login.click
        page.wait_for_timeout(5000)
      end

      email_input = page.locator('input[name="username"], input[name="email"], input[autocomplete="username"], input[type="text"]').first
      pw_input    = page.locator('input[name="password"], input[name="pass"], input[type="password"]').first

      if (email_input.visible?(timeout: 10000) rescue false)
        email_input.click
        page.wait_for_timeout(300)
        page.keyboard.type(creds[:email], delay: 50)
        page.wait_for_timeout(500)
        pw_input.click
        page.wait_for_timeout(300)
        page.keyboard.type(creds[:password], delay: 50)
        page.wait_for_timeout(1000)
        page.keyboard.press('Enter')
        page.wait_for_timeout(15000)
      end

      # ログイン後ダイアログをスキップ
      2.times do
        skip = page.locator('button:has-text("後で"), button:has-text("Not Now"), button:has-text("Not now"), button:has-text("保存しない")').first
        skip.click if (skip.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(2000)
      end

      raise '[Threads] ログインに失敗しました。接続管理画面の「ブラウザログイン」を使ってください。' if page.url.include?('login')
      log('[Threads] ✅ ログイン完了')
    end

    def build_post(title, content, event_url, ef)
      date_str = ef['startDate'].present? ? "#{ef['startDate']} #{ef['startTime']}" : ''
      lines = []
      lines << title
      lines << ''
      lines << "📅 #{date_str}" if date_str.present?
      lines << '💻 オンライン開催' if ef['place']&.include?('オンライン')
      lines << ''
      lines << '#プログラミング #エンジニア #生成AI'
      if event_url.present?
        lines << ''
        lines << '📌 お申し込みはこちら'
        lines << event_url
      end

      post = lines.join("\n")
      post.length > TEXT_LIMIT ? post[0, TEXT_LIMIT - 1] + '…' : post
    end

    def find_event_url(ef)
      return ef['eventUrl'] if ef['eventUrl'].present?
      item_id = ef['itemId'].presence
      return nil unless item_id
      history = PostingHistory.where(item_id: item_id, status: 'success')
        .where.not(event_url: [nil, '', 'about:blank'])
        .order(posted_at: :desc).first
      history&.event_url
    end

    # --- 削除・中止 ---

    def perform_delete(_page, _event_url)
      log('[Threads] 投稿削除は Threads アプリから手動で行ってください')
    end

    def perform_cancel(page, event_url)
      perform_delete(page, event_url)
    end
  end
end
