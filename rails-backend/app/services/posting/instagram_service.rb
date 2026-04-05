module Posting
  class InstagramService < BaseService
    LOGIN_URL = 'https://www.instagram.com/accounts/login/'

    private

    def execute(page, content, ef)
      ensure_login(page)

      title = extract_title(ef, content, 80)
      event_url = find_event_url(ef)
      caption = build_caption(title, content, event_url, ef)

      # 画像が必須（Instagramはテキストのみ投稿不可）
      image_path = ef['imagePath'].to_s
      unless image_path.present? && File.exist?(image_path)
        raise '[Instagram] 画像が必要です（DALL-E画像生成をONにしてください）'
      end

      log('[Instagram] 投稿作成中...')

      # 新規投稿ボタン
      page.goto('https://www.instagram.com/', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # 「作成」ボタンをクリック（サイドバーの+アイコン）
      create_btn = page.locator('[aria-label="新規投稿"], [aria-label="New post"], svg[aria-label="新規投稿"]').first
      unless (create_btn.visible?(timeout: 5000) rescue false)
        # フォールバック: テキストで探す
        create_btn = page.locator('a:has-text("作成"), span:has-text("作成")').first
      end
      unless (create_btn.visible?(timeout: 5000) rescue false)
        # サイドバーのリンク一覧から探す
        create_btn = page.evaluate(<<~JS)
          (() => {
            const links = [...document.querySelectorAll('a, div[role="button"], svg')];
            const btn = links.find(el => {
              const label = el.getAttribute('aria-label') || '';
              return /新規投稿|New post|作成|Create/i.test(label);
            });
            if (btn) { btn.click(); return true; }
            return false;
          })()
        JS
        raise '[Instagram] 新規投稿ボタンが見つかりません' unless create_btn
        page.wait_for_timeout(2000)
      end
      create_btn.click if create_btn.is_a?(Playwright::Locator) rescue nil
      page.wait_for_timeout(3000)

      # 画像アップロード
      file_input = page.locator('input[type="file"][accept*="image"]').first
      if (file_input rescue false)
        file_input.set_input_files(image_path)
        page.wait_for_timeout(5000)
        log('[Instagram] 画像アップロード完了')
      else
        raise '[Instagram] ファイル入力欄が見つかりません'
      end

      # 「次へ」ボタン（トリミング画面）
      2.times do
        next_btn = page.locator('button:has-text("次へ"), button:has-text("Next"), div[role="button"]:has-text("次へ")').first
        if (next_btn.visible?(timeout: 5000) rescue false)
          next_btn.click
          page.wait_for_timeout(2000)
        end
      end

      # キャプション入力
      caption_area = page.locator('[aria-label="キャプションを入力"], [aria-label="Write a caption"], [contenteditable="true"]').first
      if (caption_area.visible?(timeout: 5000) rescue false)
        caption_area.click
        page.keyboard.type(caption, delay: 5)
        page.wait_for_timeout(1000)
        log("[Instagram] キャプション入力完了 (#{caption.length}文字)")
      else
        log('[Instagram] ⚠️ キャプション入力欄が見つかりません')
      end

      # 「シェア」/「Share」ボタン
      share_btn = page.locator('button:has-text("シェア"), button:has-text("Share"), div[role="button"]:has-text("シェア")').first
      raise '[Instagram] シェアボタンが見つかりません' unless (share_btn.visible?(timeout: 5000) rescue false)

      share_btn.click
      page.wait_for_timeout(10000)

      log('[Instagram] ✅ 投稿完了')
    end

    def ensure_login(page)
      page.goto('https://www.instagram.com/', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # 「後で」ボタンがあればスキップ（通知許可等）
      later_btn = page.locator('button:has-text("後で"), button:has-text("Not Now"), button:has-text("Later")').first
      later_btn.click if (later_btn.visible?(timeout: 2000) rescue false)
      page.wait_for_timeout(1000)

      # ログイン済みチェック
      unless page.url.include?('login')
        home_indicator = page.locator('[aria-label="ホーム"], [aria-label="Home"]').first
        if (home_indicator.visible?(timeout: 3000) rescue false)
          log('[Instagram] ✅ ログイン済み')
          return
        end
      end

      # セッションファイルがあるのにログインできない場合はID/PW認証を試行
      log('[Instagram] ログイン中...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      creds = ServiceConnection.credentials_for('instagram')
      if creds[:email].blank?
        raise '[Instagram] ログインセッションがありません。接続管理画面の「ブラウザログイン」からInstagramにログインしてください。'
      end

      username_input = page.locator('input[name="username"]').first
      pw_input = page.locator('input[name="password"]').first

      if (username_input.visible?(timeout: 5000) rescue false)
        username_input.fill(creds[:email])
        pw_input.fill(creds[:password])
        page.wait_for_timeout(500)

        login_btn = page.locator('button[type="submit"]').first
        login_btn.click rescue nil
        page.wait_for_timeout(8000)
      end

      later_btn = page.locator('button:has-text("後で"), button:has-text("Not Now")').first
      later_btn.click if (later_btn.visible?(timeout: 3000) rescue false)
      page.wait_for_timeout(2000)

      raise '[Instagram] ログインに失敗しました。接続管理画面の「ブラウザログイン」を使ってください。' if page.url.include?('login')
      log('[Instagram] ✅ ログイン完了')
    end

    def build_caption(title, content, event_url, ef)
      date_str = ef['startDate'].present? ? "#{ef['startDate']} #{ef['startTime']}" : ''
      lines = []
      lines << title
      lines << ""
      lines << "📅 #{date_str}" if date_str.present?
      lines << "💻 オンライン開催" if ef['place']&.include?('オンライン')
      lines << ""
      # 本文から要約（最初の5行）
      body_lines = content.split("\n").reject(&:blank?).first(5)
      lines.concat(body_lines)
      if event_url.present?
        lines << ""
        lines << "📌 お申し込みはこちら"
        lines << event_url
      end
      lines << ""
      lines << "#イベント #生成AI #プログラミング #エンジニア #転職 #スキルアップ #オンラインセミナー"

      lines.join("\n")[0, 2200]
    end

    def find_event_url(ef)
      return ef['eventUrl'] if ef['eventUrl'].present?
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
      log('[Instagram] 投稿削除はInstagramアプリから手動で行ってください')
    end

    def perform_cancel(page, event_url)
      perform_delete(page, event_url)
    end
  end
end
