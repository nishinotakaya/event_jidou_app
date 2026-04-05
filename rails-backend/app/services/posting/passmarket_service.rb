module Posting
  class PassmarketService < BaseService
    LOGIN_URL  = 'https://passmarket.yahoo.co.jp/'
    CREATE_URL = 'https://passmarket.yahoo.co.jp/event/new/'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    def ensure_login(page)
      log('[PassMarket] サイトへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      creds = ServiceConnection.credentials_for('passmarket')
      raise '[PassMarket] Googleメールアドレスが未設定です' if creds[:email].blank?

      # ログイン済みチェック
      login_link = page.locator('a:has-text("ログイン"), a:has-text("Sign in"), a[href*="login"]').first
      unless (login_link.visible?(timeout: 3000) rescue false)
        log('[PassMarket] ✅ ログイン済み')
        return
      end

      login_link.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(2000)

      # Yahoo! JAPANログイン画面
      log('[PassMarket] Yahoo! JAPANログイン...')

      # Googleでログイン（Yahoo!のソーシャルログイン経由）
      google_btn = page.locator('button:has-text("Google"), a:has-text("Google"), [data-provider="google"]').first
      if (google_btn.visible?(timeout: 3000) rescue false)
        begin
          popup = page.expect_popup do
            google_btn.click
          end
          popup.wait_for_load_state('domcontentloaded', timeout: 30_000) rescue nil
          popup.wait_for_timeout(2000)

          email_input = popup.locator('input[type="email"]').first
          if (email_input.visible?(timeout: 5000) rescue false)
            email_input.fill(creds[:email])
            popup.locator('#identifierNext, button:has-text("次へ"), button:has-text("Next")').first.click
            popup.wait_for_timeout(3000)

            pw_input = popup.locator('input[type="password"]').first
            if (pw_input.visible?(timeout: 5000) rescue false)
              google_password = ENV['GOOGLE_PASSWORD'].to_s
              pw_input.fill(google_password)
              popup.locator('#passwordNext, button:has-text("次へ"), button:has-text("Next")').first.click
              popup.wait_for_timeout(5000)
            end
          end
        rescue => e
          log("[PassMarket] ⚠️ Googleログイン: #{e.message}")
        end
        page.wait_for_timeout(5000)
      else
        # Yahoo! IDでログイン
        log('[PassMarket] Yahoo! IDログインを試行...')
        id_input = page.locator('#username, input[name="login"], input[name="username"]').first
        if (id_input.visible?(timeout: 3000) rescue false)
          id_input.fill(creds[:email])
          next_btn = page.locator('#btnNext, button:has-text("次へ")').first
          next_btn.click if (next_btn.visible?(timeout: 2000) rescue false)
          page.wait_for_timeout(3000)

          pw_input = page.locator('#passwd, input[name="passwd"], input[type="password"]').first
          if (pw_input.visible?(timeout: 3000) rescue false)
            pw_input.fill(creds[:password].presence || ENV['GOOGLE_PASSWORD'].to_s)
            login_btn = page.locator('#btnSubmit, button:has-text("ログイン")').first
            login_btn.click if (login_btn.visible?(timeout: 2000) rescue false)
            page.wait_for_timeout(5000)
          end
        end
      end

      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      log("[PassMarket] ✅ ログイン処理完了 → #{page.url}")
    end

    def create_event(page, content, ef)
      log('[PassMarket] イベント作成ページへ移動...')
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      title_text = extract_title(ef, content, 100)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      # ===== イベント名 =====
      title_input = page.locator('input[name*="title"], input[name*="name"], input[placeholder*="イベント名"]').first
      if (title_input.visible?(timeout: 5000) rescue false)
        title_input.fill(title_text)
        log("[PassMarket] イベント名: #{title_text}")
      end

      # ===== 説明文 =====
      desc_area = page.locator('textarea[name*="description"], textarea[name*="detail"]').first
      if (desc_area.visible?(timeout: 3000) rescue false)
        plain_content = content.gsub(/<[^>]+>/, '').strip
        desc_area.fill(plain_content)
        log('[PassMarket] 説明文入力完了')
      else
        editor = page.locator('.ql-editor, .note-editable, [contenteditable="true"]').first
        if (editor.visible?(timeout: 3000) rescue false)
          page.evaluate(<<~JS, arg: content)
            (text) => {
              const ed = document.querySelector('.ql-editor, .note-editable, [contenteditable="true"]');
              if (ed) ed.innerHTML = text.replace(/\\n/g, '<br>');
            }
          JS
          log('[PassMarket] 説明文入力完了（リッチエディタ）')
        end
      end

      # ===== 日時 =====
      dt_inputs = page.locator('input[type="datetime-local"]')
      if (dt_inputs.count >= 1 rescue false)
        dt_inputs.first.fill("#{start_date}T#{start_time}") rescue nil
        dt_inputs.nth(1).fill("#{end_date}T#{end_time}") rescue nil
      else
        date_inputs = page.locator('input[type="date"]')
        time_inputs = page.locator('input[type="time"]')
        date_inputs.first.fill(start_date) rescue nil
        date_inputs.nth(1).fill(end_date) rescue nil
        time_inputs.first.fill(start_time) rescue nil
        time_inputs.nth(1).fill(end_time) rescue nil
      end
      log("[PassMarket] 日時: #{start_date} #{start_time} 〜 #{end_date} #{end_time}")

      # ===== 開催場所 =====
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        online_opt = page.locator('label:has-text("オンライン"), input[value*="online"]').first
        online_opt.click if (online_opt.visible?(timeout: 2000) rescue false)
        log('[PassMarket] 開催形態: オンライン')
      end

      # ===== チケット =====
      ticket_name = page.locator('input[name*="ticket_name"], input[placeholder*="チケット"]').first
      ticket_name.fill('参加チケット') if (ticket_name.visible?(timeout: 2000) rescue false)

      price_input = page.locator('input[name*="price"], input[placeholder*="金額"]').first
      price_input.fill('0') if (price_input.visible?(timeout: 2000) rescue false)

      capacity = ef['capacity'].presence || '50'
      cap_input = page.locator('input[name*="quantity"], input[name*="capacity"], input[placeholder*="枚数"], input[placeholder*="定員"]').first
      cap_input.fill(capacity) if (cap_input.visible?(timeout: 2000) rescue false)
      log("[PassMarket] チケット設定: 無料 / 定員#{capacity}")

      # ===== 画像アップロード =====
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        file_input = page.locator('input[type="file"]').first
        if (file_input.count > 0 rescue false)
          file_input.set_input_files(ef['imagePath'])
          page.wait_for_timeout(3000)
          log('[PassMarket] 画像アップロード完了')
        end
      end

      # ===== 保存 =====
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
      page.wait_for_timeout(1000)

      save_btn = page.locator('button:has-text("保存"), button:has-text("作成"), button[type="submit"], input[type="submit"]').first
      if (save_btn.visible?(timeout: 5000) rescue false)
        save_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
        log("[PassMarket] ✅ 保存完了 → #{page.url}")
      end

      # ===== 公開 =====
      if ef.dig('publishSites', 'PassMarket')
        pub_btn = page.locator('button:has-text("公開"), a:has-text("公開")').first
        if (pub_btn.visible?(timeout: 3000) rescue false)
          pub_btn.click
          page.wait_for_timeout(3000)
          confirm = page.locator('button:has-text("はい"), button:has-text("OK")').first
          confirm.click if (confirm.visible?(timeout: 2000) rescue false)
          page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
          log("[PassMarket] ✅ 公開完了 → #{page.url}")
        end
      else
        log('[PassMarket] 公開設定: 非公開（下書き）')
      end

      log("[PassMarket] ✅ 処理完了 → #{page.url}")
    end
  end
end
