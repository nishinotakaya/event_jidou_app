module Posting
  class LumaService < BaseService
    SIGNIN_URL = 'https://lu.ma/signin'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    def ensure_login(page)
      log('[Luma] ホームページへ移動...')
      page.goto('https://lu.ma/home', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # ログイン済みチェック
      unless page.url.include?('/signin')
        create_btn = page.locator('button:has-text("Create"), a:has-text("Create"), button:has-text("イベント作成"), a:has-text("イベント作成")').first
        if (create_btn.visible?(timeout: 5000) rescue false)
          log('[Luma] ✅ ログイン済み（セッション復元）')
          return
        end
      end

      # セッションがない場合はブラウザログインを促す
      raise '[Luma] ログインが必要です。接続管理画面の「ブラウザログイン」からGoogleログインしてください。'
    end

    def create_event(page, content, ef)
      log('[Luma] イベント作成...')

      page.goto('https://lu.ma/home', waitUntil: 'domcontentloaded', timeout: 30_000) rescue nil
      page.wait_for_timeout(2000)

      create_btn = page.locator('button:has-text("Create Event"), button:has-text("Create"), a:has-text("Create Event"), button:has-text("イベント作成"), a:has-text("イベント作成")').first
      if (create_btn.visible?(timeout: 5000) rescue false)
        create_btn.click
        page.wait_for_timeout(3000)
      else
        page.goto('https://lu.ma/create', waitUntil: 'domcontentloaded', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
      end

      log("[Luma] イベント作成画面 → #{page.url}")

      title_text = extract_title(ef, content, 100)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      # タイトル
      title_area = page.locator('textarea[placeholder="イベント名"], textarea[placeholder*="Event Name"]').first
      if (title_area.visible?(timeout: 5000) rescue false)
        title_area.fill(title_text)
        log("[Luma] タイトル: #{title_text}")
      end

      # 時間入力
      page.wait_for_timeout(1000)
      time_inputs = page.locator('input[type="time"]')
      if (time_inputs.count >= 2 rescue false)
        time_inputs.first.fill(start_time)
        time_inputs.nth(1).fill(end_time)
        log("[Luma] 時間: #{start_time} 〜 #{end_time}")
      end

      # 日付入力（JS経由でinput値を直接変更）
      target_date = Date.parse(start_date)
      date_display = "#{target_date.month}月#{target_date.day}日(#{%w[日 月 火 水 木 金 土][target_date.wday]})"
      page.evaluate(<<~JS, arg: { display: date_display, iso: start_date })
        (d) => {
          const inputs = document.querySelectorAll('input[type="text"]');
          inputs.forEach(input => {
            if (input.value && input.value.match(/月.*日/)) {
              const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
              setter.call(input, d.display);
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
            }
          });
        }
      JS
      log("[Luma] 日付: #{date_display}")

      # 画像アップロード
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        file_input = page.locator('input[type="file"]').first
        if (file_input.count > 0 rescue false)
          file_input.set_input_files(ef['imagePath'])
          page.wait_for_timeout(3000)
          log('[Luma] 画像アップロード完了')
        end
      end

      # モーダルオーバーレイがあれば閉じる
      page.keyboard.press('Escape') rescue nil
      page.wait_for_timeout(500)

      # 「イベント作成」ボタン（button[type="submit"]）
      page.wait_for_timeout(500)
      save_btn = page.locator('button[type="submit"]:has-text("イベント作成"), button[type="submit"]:has-text("Create Event")').first
      if (save_btn.visible?(timeout: 5000) rescue false)
        save_btn.click(force: true)
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(5000)
        log("[Luma] ✅ イベント作成完了 → #{page.url}")
      else
        log('[Luma] ⚠️ イベント作成ボタンが見つかりません')
      end

      log("[Luma] ✅ 処理完了 → #{page.url}")
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      # 「その他」タブに遷移（削除はここにある）
      more_url = event_url.sub(/\/?$/, '') + '/more'
      page.goto(more_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      log('[Luma] 「その他」ページで削除ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil

      # ページ下部にスクロール
      page.evaluate('() => window.scrollTo(0, document.body.scrollHeight)')
      page.wait_for_timeout(1000)

      del_btn = page.locator('button:has-text("Delete"), button:has-text("Delete Event"), a:has-text("Delete")').first
      if (del_btn.visible?(timeout: 5000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        # 確認モーダル
        confirm = page.locator('button:has-text("Delete"), button:has-text("Yes"), button:has-text("Confirm")').last
        confirm.click if (confirm.visible?(timeout: 5000) rescue false)
        page.wait_for_timeout(3000)
        log('[Luma] ✅ イベント削除完了')
      else
        raise '[Luma] 削除ボタンが見つかりません'
      end
    end

    def perform_cancel(page, event_url)
      ensure_login(page)
      more_url = event_url.sub(/\/?$/, '') + '/more'
      page.goto(more_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      log('[Luma] 「その他」ページで中止ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil

      cancel_btn = page.locator('button:has-text("Cancel Event"), button:has-text("Cancel"), a:has-text("Cancel Event")').first
      if (cancel_btn.visible?(timeout: 5000) rescue false)
        cancel_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("Cancel"), button:has-text("Yes"), button:has-text("Confirm")').last
        confirm.click if (confirm.visible?(timeout: 5000) rescue false)
        page.wait_for_timeout(3000)
        log('[Luma] ✅ イベント中止完了')
      else
        # フォールバック: 削除
        log('[Luma] 中止ボタンなし → 削除で対応')
        perform_delete(page, event_url)
      end
    end
  end
end
