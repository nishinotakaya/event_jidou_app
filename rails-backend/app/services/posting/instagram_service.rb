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

      page.goto('https://www.instagram.com/', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      # 「新しい投稿」ボタンをクリック（サイドバーSVGアイコン）
      clicked = page.evaluate(<<~'JS')
        (() => {
          const svg = document.querySelector('svg[aria-label="新しい投稿"]') ||
                      document.querySelector('svg[aria-label="新規投稿"]') ||
                      document.querySelector('svg[aria-label="New post"]');
          if (svg) {
            const link = svg.closest('a') || svg.closest('div[role="button"]') || svg.parentElement;
            link.click();
            return true;
          }
          return false;
        })()
      JS
      raise '[Instagram] 新規投稿ボタンが見つかりません' unless clicked
      page.wait_for_timeout(3000)

      # 画像アップロード
      file_input = page.locator('input[type="file"]').first
      file_input.set_input_files(image_path)
      page.wait_for_timeout(5000)
      log('[Instagram] 画像アップロード完了')

      # 「次へ」ボタン×2（トリミング→フィルター→キャプション画面）
      2.times do |i|
        page.wait_for_timeout(2000)
        result = page.evaluate(<<~'JS')
          (() => {
            const dlg = document.querySelector('div[role="dialog"]');
            if (!dlg) return 'no dialog';
            const all = [...dlg.querySelectorAll('button, div[role="button"]')];
            const btn = all.find(b => /^次へ$|^Next$/.test(b.textContent?.trim()));
            if (btn) { btn.click(); return true; }
            return false;
          })()
        JS
        log("[Instagram] 次へ(#{i + 1}/2): #{result}")
        page.wait_for_timeout(2000)
      end

      # キャプション入力
      caption_area = page.locator('div[role="dialog"] [aria-label*="キャプション"], div[role="dialog"] [aria-label*="caption"], div[role="dialog"] [contenteditable="true"]').first
      if (caption_area.visible?(timeout: 5000) rescue false)
        caption_area.click
        page.keyboard.type(caption, delay: 5)
        page.wait_for_timeout(1000)
        log("[Instagram] キャプション入力完了 (#{caption.length}文字)")
      else
        log('[Instagram] ⚠️ キャプション入力欄が見つかりません')
      end

      # 「シェア」ボタン
      page.wait_for_timeout(2000)
      shared = page.evaluate(<<~'JS')
        (() => {
          const dlg = document.querySelector('div[role="dialog"]');
          if (!dlg) return false;
          const all = [...dlg.querySelectorAll('button, div[role="button"]')];
          const btn = all.find(b => /^シェア$|^Share$/.test(b.textContent?.trim()));
          if (btn) { btn.click(); return true; }
          return false;
        })()
      JS
      raise '[Instagram] シェアボタンが見つかりません' unless shared

      page.wait_for_timeout(10000)
      log('[Instagram] ✅ 投稿完了')
    end

    def ensure_login(page)
      page.goto('https://www.instagram.com/', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      # 「後で」ボタンがあればスキップ（通知許可等）
      later_btn = page.locator('button:has-text("後で"), button:has-text("Not Now"), button:has-text("Later")').first
      later_btn.click if (later_btn.visible?(timeout: 2000) rescue false)
      page.wait_for_timeout(1000)

      # ログイン済みチェック
      unless page.url.include?('login')
        home_indicator = page.locator('svg[aria-label="ホーム"], svg[aria-label="Home"]').first
        if (home_indicator.visible?(timeout: 5000) rescue false)
          log('[Instagram] ✅ ログイン済み')
          return
        end
      end

      # ID/PW認証
      log('[Instagram] ログイン中...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      creds = ServiceConnection.credentials_for('instagram')
      if creds[:email].blank?
        raise '[Instagram] ログイン情報がありません。接続管理画面から設定してください。'
      end

      # 幅広いセレクタでフォームを探す（Instagram/Meta統合ログイン対応）
      email_input = page.locator('input[name="username"], input[name="email"], input[type="text"]').first
      pw_input = page.locator('input[name="password"], input[name="pass"], input[type="password"]').first

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

      # ダイアログスキップ（ログイン情報保存・通知許可等）
      2.times do
        later_btn = page.locator('button:has-text("後で"), button:has-text("Not Now"), button:has-text("Not now"), button:has-text("保存しない")').first
        later_btn.click if (later_btn.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(2000)
      end

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
