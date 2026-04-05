module Posting
  class TwitterService < BaseService
    LOGIN_URL = 'https://x.com/i/flow/login'

    private

    def execute(page, content, ef)
      ensure_login(page)

      title = extract_title(ef, content, 60)

      # イベントURLを取得（こくチーズ等の申し込みURL）
      event_url = find_event_url(ef)

      # ツイート本文を組み立て（140文字制限を意識して短く）
      tweet = build_tweet(title, content, event_url, ef)

      log("[X] ツイート投稿中...")
      log("[X] 内容: #{tweet[0, 100]}...")

      # ホーム画面に遷移
      page.goto('https://x.com/home', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # 投稿欄をクリック
      compose = page.locator('[data-testid="tweetTextarea_0"], [role="textbox"][data-testid="tweetTextarea_0"]').first
      unless (compose.visible?(timeout: 5000) rescue false)
        # フォールバック: 「いまどうしてる？」テキストエリア
        compose = page.locator('[role="textbox"]').first
      end
      raise '[X] 投稿欄が見つかりません' unless (compose.visible?(timeout: 5000) rescue false)

      compose.click
      page.wait_for_timeout(500)

      # テキスト入力（Playwright keyboard.type でIME問題を回避）
      page.keyboard.type(tweet, delay: 10)
      page.wait_for_timeout(1000)

      # 画像添付（DALL-E画像があれば）
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        file_input = page.locator('input[type="file"][accept*="image"]').first
        if (file_input rescue false)
          file_input.set_input_files(ef['imagePath'])
          page.wait_for_timeout(3000)
          log('[X] 画像添付完了')
        end
      end

      # 投稿ボタンをクリック
      post_btn = page.locator('[data-testid="tweetButtonInline"], [data-testid="tweetButton"]').first
      raise '[X] 投稿ボタンが見つかりません' unless (post_btn.visible?(timeout: 5000) rescue false)

      post_btn.click
      page.wait_for_timeout(5000)

      log('[X] ✅ ツイート投稿完了')
    end

    def ensure_login(page)
      # セッションファイルベースのログイン（手動ログイン後にセッション保存済み前提）
      page.goto('https://x.com/home', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # ログイン済みチェック
      if page.url.include?('/home') && !page.url.include?('login')
        compose = page.locator('[data-testid="tweetTextarea_0"], [role="textbox"]').first
        if (compose.visible?(timeout: 5000) rescue false)
          log('[X] ✅ ログイン済み')
          return
        end
      end

      # セッションが無い場合はブラウザログインを促す
      raise '[X] ログインセッションがありません。接続管理画面の「ブラウザログイン」からXにログインしてください。'
    end

    def build_tweet(title, content, event_url, ef)
      date_str = ef['startDate'].present? ? "#{ef['startDate']} #{ef['startTime']}" : ''
      lines = []
      lines << title
      lines << ""
      lines << "📅 #{date_str}" if date_str.present?
      lines << "💻 オンライン開催" if ef['place']&.include?('オンライン')
      lines << ""
      lines << "#イベント #生成AI #プログラミング #エンジニア転職"
      if event_url.present?
        lines << ""
        lines << "📌 お申し込みはこちら"
        lines << event_url
      end

      tweet = lines.join("\n")
      tweet.length > 270 ? tweet[0, 267] + '...' : tweet
    end

    def find_event_url(ef)
      # publishSitesからイベントURLを探す（こくチーズ優先）
      return ef['eventUrl'] if ef['eventUrl'].present?

      # PostingHistoryから最新の公開イベントURLを取得
      item_id = ef['itemId'].presence
      if item_id
        history = PostingHistory.where(item_id: item_id, status: 'success')
          .where.not(event_url: [nil, '', 'about:blank'])
          .order(posted_at: :desc).first
        return history.event_url if history
      end
      nil
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      log('[X] ツイート削除はX管理画面から手動で行ってください')
      # ツイートURLが保存されていれば削除可能だが、通常はURLが取得できない
    end

    def perform_cancel(page, event_url)
      perform_delete(page, event_url)
    end
  end
end
