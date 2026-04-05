module Posting
  class SeminarsService < BaseService
    LOGIN_URL  = 'https://seminars.jp/users/sign_in'
    CREATE_URL = 'https://seminars.jp/user/host/seminar/seminars/new'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    # ===== ログイン =====
    def ensure_login(page)
      log('[セミナーズ] ログインページへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      # ログインフォームがなければログイン済み
      has_login_form = (page.locator('input[type="email"], #user_email').first.visible?(timeout: 2000) rescue false)
      unless has_login_form
        log('[セミナーズ] ✅ ログイン済み')
        return
      end

      creds = ServiceConnection.credentials_for('seminars')
      raise '[セミナーズ] メールアドレスが未設定です' if creds[:email].blank?

      page.locator('input[type="email"], #user_email, input[name*="email"]').first.fill(creds[:email])
      page.locator('input[type="password"], input[name*="password"]').first.fill(creds[:password])
      page.locator('input[name="commit"], input[type="submit"]').first.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      # ログイン成功確認（sign_inページから離れていること）
      if page.url.include?('/sign_in')
        raise '[セミナーズ] ログイン失敗'
      end

      log("[セミナーズ] ✅ ログイン完了 → #{page.url}")
    end

    # ===== イベント作成 =====
    def create_event(page, content, ef)
      log('[セミナーズ] イベント作成ページへ移動...')
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # プロフィール編集にリダイレクトされた場合は入力して保存
      if page.url.include?('/profile/edit') || page.url.include?('/profile')
        log('[セミナーズ] プロフィール入力が必要です...')
        complete_profile(page)
        page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
        page.wait_for_timeout(3000)
      end

      log("[セミナーズ] フォーム → #{page.url}")

      # ----- タイトル -----
      title_text = extract_title(ef, content, 100)
      title_input = page.locator('input[name*="title"],input[name*="name"],input#title,input#seminar_title').first
      if (title_input.visible?(timeout: 3000) rescue false)
        title_input.fill(title_text)
        log("[セミナーズ] タイトル入力: #{title_text}")
      else
        # フォーム構造が異なる場合: 最初のテキスト入力を使用
        first_input = page.locator('input[type="text"]').first
        if (first_input.visible?(timeout: 2000) rescue false)
          first_input.fill(title_text)
          log("[セミナーズ] タイトル入力（代替セレクタ）: #{title_text}")
        else
          raise '[セミナーズ] タイトル入力欄が見つかりません'
        end
      end

      # ----- 説明文 -----
      desc_area = page.locator('textarea[name*="description"],textarea[name*="content"],textarea[name*="body"],textarea#description').first
      if (desc_area.visible?(timeout: 3000) rescue false)
        desc_area.fill(content)
        log('[セミナーズ] 説明文入力完了')
      else
        # リッチエディタ対応
        page.evaluate(<<~JS, arg: content)
          (text) => {
            const editors = document.querySelectorAll('textarea, [contenteditable="true"], .ql-editor, .tox-edit-area__iframe');
            for (const el of editors) {
              if (el.tagName === 'TEXTAREA') { el.value = text; el.dispatchEvent(new Event('input', { bubbles: true })); return; }
              if (el.contentEditable === 'true') { el.innerHTML = text.replace(/\\n/g, '<br>'); return; }
            }
          }
        JS
        log('[セミナーズ] 説明文入力完了（エディタ経由）')
      end

      # ----- 開催日時 -----
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      fill_date_input(page, 'start', start_date, start_time)
      fill_date_input(page, 'end', end_date, end_time)

      # ----- 開催形式: オンライン -----
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        online_opt = page.locator("input[value*='online'],label:has-text('オンライン') input,input[name*='online']").first
        if (online_opt.visible?(timeout: 2000) rescue false)
          online_opt.check unless (online_opt.checked? rescue false)
          log('[セミナーズ] 開催形式: オンラインを選択')
        end
      end

      # ----- 定員 -----
      capacity = ef['capacity'].presence || '50'
      cap_input = page.locator('input[name*="capacity"],input[name*="limit"],input#capacity').first
      if (cap_input.visible?(timeout: 2000) rescue false)
        cap_input.fill(capacity.to_s)
        log("[セミナーズ] 定員入力: #{capacity}")
      end

      # ----- 参加費: 無料 -----
      free_opt = page.locator("input[value='0'],input[value='free'],label:has-text('無料') input").first
      if (free_opt.visible?(timeout: 2000) rescue false)
        free_opt.check unless (free_opt.checked? rescue false)
        log('[セミナーズ] 参加費: 無料を選択')
      end

      # ----- 保存 -----
      log('[セミナーズ] 保存ボタンをクリック...')
      save_btn = page.locator("button[type='submit']:has-text('保存'),button[type='submit']:has-text('登録'),input[type='submit']").first
      unless (save_btn.visible?(timeout: 3000) rescue false)
        save_btn = page.locator("button[type='submit']").first
      end
      raise '[セミナーズ] 保存ボタンが見つかりません' unless (save_btn.visible?(timeout: 3000) rescue false)

      save_btn.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)
      log("[セミナーズ] ✅ 保存完了 → #{page.url}")

      # ----- 公開 -----
      if ef.dig('publishSites', 'セミナーズ')
        log('[セミナーズ] 公開処理を実行...')
        publish_event(page)
      else
        log('[セミナーズ] 公開設定: 非公開（下書き保存のみ）')
      end

      log("[セミナーズ] ✅ 処理完了 → #{page.url}")
    end

    # ===== 日時入力ヘルパー =====
    def fill_date_input(page, type, date, time)
      label = type == 'start' ? '開始' : '終了'

      # 日付入力
      date_input = page.locator("input[name*='#{type}_date'],input[name*='#{type}Date'],input[name*='date_#{type}']").first
      if (date_input.visible?(timeout: 2000) rescue false)
        set_input_value(page, date_input, date)
        log("[セミナーズ] #{label}日付入力: #{date}")
      end

      # 時刻入力
      time_input = page.locator("input[name*='#{type}_time'],input[name*='#{type}Time'],input[name*='time_#{type}']").first
      if (time_input.visible?(timeout: 2000) rescue false)
        set_input_value(page, time_input, time)
        log("[セミナーズ] #{label}時刻入力: #{time}")
      else
        # 日時一体型
        datetime_input = page.locator("input[name*='#{type}'],input[type='datetime-local']").first
        if (datetime_input.visible?(timeout: 2000) rescue false)
          set_input_value(page, datetime_input, "#{date}T#{time}")
          log("[セミナーズ] #{label}日時入力: #{date} #{time}")
        end
      end
    end

    def set_input_value(page, locator, value)
      locator.click
      page.wait_for_timeout(200)
      locator.fill(value)
      page.keyboard.press('Escape') rescue nil
      page.wait_for_timeout(200)
    end

    # ===== プロフィール自動入力 =====
    def complete_profile(page)
      # 名前（姓・名・セイ・メイ）
      text_inputs = page.locator('input[type="text"]').all.select { |el| (el.visible?(timeout: 500) rescue false) }
      placeholders = text_inputs.map { |el| el.get_attribute('placeholder').to_s rescue '' }

      text_inputs.each_with_index do |el, i|
        ph = placeholders[i]
        val = el.input_value.to_s.strip rescue ''
        next if val.present?

        case ph
        when /姓|日本/   then el.fill('西野')
        when /名|太郎/   then el.fill('貴也')
        when /せい|にほん/ then el.fill('にしの')
        when /めい|たろう/ then el.fill('たかや')
        when /電話/       then el.fill('09012345678')
        end
      end

      # 生年月日（select）
      selects = page.locator('select').all.select { |el| (el.visible?(timeout: 500) rescue false) }
      selects.each do |sel|
        opts = sel.evaluate('el => Array.from(el.options).map(o => o.text)') rescue []
        if opts.any? { |o| o.include?('1990') }
          sel.select_option(label: '1990') rescue nil
        elsif opts.any? { |o| o.include?('1月') || o == '1' }
          sel.select_option(index: 1) rescue nil
        end
      end

      # 保存ボタン
      save_btn = page.locator('input[name="commit"], button[type="submit"]:has-text("保存"), button[type="submit"]:has-text("更新")').first
      if (save_btn.visible?(timeout: 3000) rescue false)
        save_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
        log('[セミナーズ] プロフィール保存完了')
      end
    end

    # ===== 公開 =====
    def publish_event(page)
      publish_btn = nil
      ['公開する', '公開', '掲載する', '掲載'].each do |text|
        btn = page.locator("button:has-text('#{text}'), a:has-text('#{text}'), input[value='#{text}']").first
        if (btn.visible?(timeout: 2000) rescue false)
          publish_btn = btn
          break
        end
      end

      if publish_btn
        publish_btn.click
        page.wait_for_timeout(2000)

        # 確認ダイアログ
        ['はい', 'OK', '公開する', '掲載する', '確認'].each do |text|
          confirm = page.locator("button:has-text('#{text}')").first
          if (confirm.visible?(timeout: 2000) rescue false)
            confirm.click
            page.wait_for_timeout(2000)
            break
          end
        end

        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        log("[セミナーズ] ✅ 公開完了 → #{page.url}")
      else
        log('[セミナーズ] ⚠️ 公開ボタンが見つかりません')
      end
    end
  end
end
