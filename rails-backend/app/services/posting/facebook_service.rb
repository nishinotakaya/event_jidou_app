module Posting
  class FacebookService < BaseService
    LOGIN_URL = 'https://www.facebook.com/login'
    HOME_URL  = 'https://www.facebook.com/'

    private

    def execute(page, content, ef)
      ensure_login(page)

      title = extract_title(ef, content, 80)
      event_url = find_event_url(ef)
      body = build_body(title, content, event_url)

      log('[Facebook] 投稿作成中...')
      page.goto(HOME_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # 「何か新しいことを投稿しますか？」入力欄を開く
      opener = page.locator('div[role="button"]:has-text("その気持ち"), div[role="button"]:has-text("What\'s on your mind"), div[role="button"]:has-text("投稿")').first
      if (opener.visible?(timeout: 5000) rescue false)
        opener.click
        page.wait_for_timeout(2500)
      else
        raise '[Facebook] 投稿入力欄が見つかりません（ログイン状態を確認してください）'
      end

      # テキスト入力（contenteditable）
      editor = page.locator('div[role="dialog"] div[contenteditable="true"], div[contenteditable="true"][aria-label*="投稿"], div[contenteditable="true"][aria-label*="mind"]').first
      unless (editor.visible?(timeout: 5000) rescue false)
        raise '[Facebook] テキスト入力欄が見つかりません'
      end
      editor.click
      page.keyboard.type(body, delay: 10)
      log("[Facebook] テキスト入力完了 (#{body.length}文字)")
      page.wait_for_timeout(1500)

      # 画像アップロード（任意）
      image_path = ef['imagePath'].to_s
      if image_path.present? && File.exist?(image_path)
        file_input = page.locator('div[role="dialog"] input[type="file"]').first
        if (file_input.count > 0 rescue false)
          file_input.set_input_files(image_path)
          page.wait_for_timeout(3000)
          log('[Facebook] 画像アップロード完了')
        end
      end

      # 「投稿」ボタン
      post_btn = page.locator('div[role="dialog"] div[role="button"]:has-text("投稿"), div[role="dialog"] div[role="button"]:has-text("Post")').last
      if (post_btn.visible?(timeout: 5000) rescue false)
        post_btn.click
        page.wait_for_timeout(5000)
        log("[Facebook] ✅ 投稿完了 → #{page.url}")
      else
        raise '[Facebook] 投稿ボタンが見つかりません'
      end
    end

    def ensure_login(page)
      log('[Facebook] ログイン状態を確認中...')
      page.goto(HOME_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      if page.url.include?('login') || page.url.include?('checkpoint')
        raise '[Facebook] ログインが必要です。接続管理画面の「ブラウザログイン」からログインしてください。'
      end
      log('[Facebook] ✅ ログイン済み')
    end

    def build_body(title, content, event_url)
      body = String.new
      body << title << "\n\n" if title.present? && !content.to_s.start_with?(title)
      body << content.to_s.strip
      body << "\n\n▼ 詳細・お申し込みはこちら\n" << event_url if event_url.present?
      body
    end

    def find_event_url(ef)
      item_id = ef['itemId']
      return nil unless item_id.present?
      h = PostingHistory.where(item_id: item_id, status: 'success').where.not(event_url: [nil, '']).order(posted_at: :desc).first
      h&.event_url
    rescue
      nil
    end
  end
end
