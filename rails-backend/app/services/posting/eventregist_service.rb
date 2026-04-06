module Posting
  class EventregistService < BaseService
    LOGIN_URL = 'https://eventregist.com/login'
    BASE_URL  = 'https://eventregist.com'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    def ensure_login(page)
      # まずダッシュボードに直接アクセス（セッションが有効ならログイン不要）
      log('[EventRegist] ログインページへ移動...')
      page.goto("#{BASE_URL}/ticket/list", waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      unless page.url.include?('/login') || page.url.include?('/signin')
        log("[EventRegist] ✅ ログイン済み → #{page.url}")
        return
      end

      creds = ServiceConnection.credentials_for('eventregist')
      raise '[EventRegist] メールアドレスが未設定です' if creds[:email].blank?

      log("[EventRegist] ログインフォーム入力中... (URL: #{page.url})")
      # メールアドレス入力
      email_input = page.locator('input[type="email"], input[name="email"], input[placeholder*="メール"], input[placeholder*="mail"]').first
      unless (email_input.visible?(timeout: 5000) rescue false)
        # ページの状態をデバッグ
        body = page.evaluate("document.body?.innerText?.substring(0, 200) || ''") rescue ''
        raise "[EventRegist] メール入力欄が見つかりません (URL: #{page.url}, body: #{body[0, 80]})"
      end
      email_input.fill(creds[:email])

      # パスワード入力
      pw_input = page.locator('input[type="password"]').first
      raise '[EventRegist] パスワード入力欄が見つかりません' unless (pw_input.visible?(timeout: 3000) rescue false)
      pw_input.fill(creds[:password])

      # ログインボタン
      login_btn = page.locator('button[type="submit"], input[type="submit"], button:has-text("ログイン"), button:has-text("Sign in"), button:has-text("Login")').first
      login_btn.click if (login_btn.visible?(timeout: 3000) rescue false)

      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      if page.url.include?('/login')
        raise '[EventRegist] ログイン失敗'
      end
      log("[EventRegist] ✅ ログイン完了 → #{page.url}")
    end

    def create_event(page, content, ef)
      log('[EventRegist] イベント作成ページへ移動...')

      # ダッシュボードから「新しいイベントを作る」ボタンを探す
      page.goto(BASE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      # 新規作成リンクを探す
      create_link = page.locator('a:has-text("新しいイベント"), a:has-text("Create"), a:has-text("イベントを作成"), a[href*="event/new"], a[href*="events/new"]').first
      if (create_link.visible?(timeout: 5000) rescue false)
        create_link.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
      else
        # 直接URLを試行
        page.goto("#{BASE_URL}/event/new", waitUntil: 'domcontentloaded', timeout: 30_000)
        page.wait_for_timeout(3000)
      end
      log("[EventRegist] イベント作成画面 → #{page.url}")

      # STEP 1: 基本情報
      title_text = extract_title(ef, content, 150)

      # イベント名
      name_input = page.locator('input[name*="name"], input[name*="title"], input[placeholder*="イベント名"], input[placeholder*="Event"]').first
      if (name_input.visible?(timeout: 5000) rescue false)
        name_input.fill(title_text)
        log("[EventRegist] イベント名: #{title_text}")
      else
        # テキストエリアの可能性
        page.locator('textarea').first.fill(title_text) rescue nil
        log("[EventRegist] イベント名入力（textarea）: #{title_text}")
      end

      # 次へボタン（ウィザード形式の場合）
      click_next_button(page)
      page.wait_for_timeout(2000)

      # STEP 2: 日時・場所
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      # 日時入力（datetime-local, date + time, カレンダーウィジェット等に対応）
      fill_datetime_inputs(page, start_date, start_time, end_date, end_time)

      # 開催形式（オンライン）
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        online_opt = page.locator('label:has-text("オンライン"), input[value*="online"], label:has-text("Online"), input[value*="Online"]').first
        if (online_opt.visible?(timeout: 3000) rescue false)
          online_opt.click
          page.wait_for_timeout(1000)
          log('[EventRegist] 開催形式: オンライン')

          # Zoom URL
          zoom_url = ef['zoomUrl'].presence
          if zoom_url.present?
            url_input = page.locator('input[name*="url"], input[placeholder*="URL"], input[name*="streaming"]').first
            if (url_input.visible?(timeout: 3000) rescue false)
              url_input.fill(zoom_url)
              log("[EventRegist] 配信URL: #{zoom_url}")
            end
          end
        end
      end

      click_next_button(page)
      page.wait_for_timeout(2000)

      # STEP 3: チケット
      ticket_name_input = page.locator('input[name*="ticket_name"], input[placeholder*="チケット"], input[placeholder*="Ticket"]').first
      if (ticket_name_input.visible?(timeout: 5000) rescue false)
        ticket_name_input.fill('参加チケット')
        log('[EventRegist] チケット名: 参加チケット')
      end

      # 無料チケット
      free_check = page.locator('input[type="checkbox"][name*="free"], label:has-text("無料"), label:has-text("Free")').first
      if (free_check.visible?(timeout: 2000) rescue false)
        free_check.click unless (free_check.checked? rescue false)
        log('[EventRegist] 無料チケット設定')
      else
        # 価格を0に
        price_input = page.locator('input[name*="price"], input[placeholder*="金額"]').first
        price_input.fill('0') if (price_input.visible?(timeout: 2000) rescue false)
      end

      # 定員
      capacity = ef['capacity'].presence || '50'
      qty_input = page.locator('input[name*="quantity"], input[name*="capacity"], input[name*="limit"], input[placeholder*="数量"], input[placeholder*="定員"]').first
      if (qty_input.visible?(timeout: 2000) rescue false)
        qty_input.fill(capacity)
        log("[EventRegist] 定員: #{capacity}")
      end

      click_next_button(page)
      page.wait_for_timeout(2000)

      # STEP 4: 確認・保存
      # 「後で設定」や「スキップ」ボタンがあれば押す
      skip_btn = page.locator('button:has-text("後で"), a:has-text("後で"), button:has-text("スキップ"), button:has-text("Skip")').first
      skip_btn.click if (skip_btn.visible?(timeout: 2000) rescue false)
      page.wait_for_timeout(1000)

      # 保存ボタン
      save_btn = page.locator('button:has-text("保存"), button:has-text("作成"), button:has-text("Save"), button:has-text("Create"), input[type="submit"]').first
      if (save_btn.visible?(timeout: 5000) rescue false)
        save_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
        log("[EventRegist] ✅ イベント作成完了 → #{page.url}")
      end

      # 説明文入力（作成後の編集画面）
      fill_description(page, content)

      # 公開処理
      if ef.dig('publishSites', 'EventRegist')
        publish_event(page)
      else
        log('[EventRegist] 公開設定: 非公開（下書き保存のみ）')
      end

      # イベントURLを取得（ページ内またはURLパターンから）
      event_url = page.evaluate(<<~JS) rescue page.url
        () => {
          const links = [...document.querySelectorAll('a[href*="/e/"], a[href*="/event/"]')];
          const match = links.find(a => /eventregist\.com\/e\//.test(a.href));
          return match ? match.href : location.href;
        }
      JS
      log("[EventRegist] ✅ 処理完了 → #{event_url}")
    end

    def fill_datetime_inputs(page, start_date, start_time, end_date, end_time)
      # datetime-local対応
      datetime_inputs = page.locator('input[type="datetime-local"]')
      if (datetime_inputs.count >= 2 rescue false)
        datetime_inputs.first.fill("#{start_date}T#{start_time}")
        datetime_inputs.nth(1).fill("#{end_date}T#{end_time}")
        log("[EventRegist] 日時: #{start_date} #{start_time} 〜 #{end_date} #{end_time}")
        return
      end

      # date + time 分離型
      date_inputs = page.locator('input[type="date"]')
      time_inputs = page.locator('input[type="time"]')
      if (date_inputs.count >= 1 rescue false)
        date_inputs.first.fill(start_date) rescue nil
        date_inputs.nth(1).fill(end_date) rescue nil
        time_inputs.first.fill(start_time) rescue nil
        time_inputs.nth(1).fill(end_time) rescue nil
        log("[EventRegist] 日時: #{start_date} #{start_time} 〜 #{end_date} #{end_time}")
        return
      end

      # テキスト入力型
      page.evaluate(<<~JS, arg: { sd: start_date, st: start_time, ed: end_date, et: end_time })
        (d) => {
          const inputs = document.querySelectorAll('input');
          inputs.forEach(input => {
            const ph = (input.placeholder || '').toLowerCase();
            const name = (input.name || '').toLowerCase();
            if (ph.includes('開始日') || name.includes('start_date')) input.value = d.sd;
            if (ph.includes('開始時') || name.includes('start_time')) input.value = d.st;
            if (ph.includes('終了日') || name.includes('end_date')) input.value = d.ed;
            if (ph.includes('終了時') || name.includes('end_time')) input.value = d.et;
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
          });
        }
      JS
      log("[EventRegist] 日時入力（JS経由）: #{start_date} #{start_time} 〜 #{end_date} #{end_time}")
    end

    def fill_description(page, content)
      # リッチテキストエディタ or textarea
      editor = page.locator('.ql-editor, .note-editable, [contenteditable="true"], .ProseMirror').first
      if (editor.visible?(timeout: 3000) rescue false)
        page.evaluate(<<~JS, arg: content)
          (text) => {
            const editor = document.querySelector('.ql-editor, .note-editable, [contenteditable="true"], .ProseMirror');
            if (editor) { editor.innerHTML = text.replace(/\\n/g, '<br>'); }
          }
        JS
        log('[EventRegist] 説明文入力完了（リッチエディタ）')
      else
        desc_area = page.locator('textarea[name*="description"], textarea[name*="overview"]').first
        if (desc_area.visible?(timeout: 3000) rescue false)
          desc_area.fill(content)
          log('[EventRegist] 説明文入力完了')
        end
      end
    end

    def click_next_button(page)
      next_btn = page.locator('button:has-text("次へ"), button:has-text("Next"), a:has-text("次へ"), button:has-text("進む")').first
      next_btn.click if (next_btn.visible?(timeout: 2000) rescue false)
    end

    def publish_event(page)
      publish_btn = page.locator('button:has-text("公開"), button:has-text("Publish"), a:has-text("公開")').first
      if (publish_btn.visible?(timeout: 5000) rescue false)
        publish_btn.click
        page.wait_for_timeout(3000)
        # 確認ダイアログ
        confirm_btn = page.locator('button:has-text("はい"), button:has-text("OK"), button:has-text("確認")').first
        confirm_btn.click if (confirm_btn.visible?(timeout: 2000) rescue false)
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        log("[EventRegist] ✅ 公開完了 → #{page.url}")
      else
        log('[EventRegist] ⚠️ 公開ボタンが見つかりません')
      end
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[EventRegist] 削除ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      del_btn = page.locator('a:has-text("削除"), button:has-text("削除"), a:has-text("Delete"), button:has-text("Delete")').first
      if (del_btn.visible?(timeout: 5000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes"), button:has-text("Delete")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[EventRegist] ✅ イベント削除完了')
      else
        raise '[EventRegist] 削除ボタンが見つかりません'
      end
    end

    def perform_cancel(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[EventRegist] 中止処理中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      cancel_btn = page.locator('a:has-text("中止"), button:has-text("中止"), a:has-text("キャンセル"), button:has-text("Cancel"), a:has-text("Cancel")').first
      if (cancel_btn.visible?(timeout: 5000) rescue false)
        cancel_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("中止"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[EventRegist] ✅ イベント中止完了')
      else
        raise '[EventRegist] 中止ボタンが見つかりません'
      end
    end
  end
end
