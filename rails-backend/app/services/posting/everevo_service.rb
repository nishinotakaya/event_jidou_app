module Posting
  class EverevoService < BaseService
    LOGIN_URL  = 'https://everevo.com/login'
    CREATE_URL = 'https://everevo.com/event/new'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    def ensure_login(page)
      log('[everevo] ログインページへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      if page.url.include?('/event/') && !page.url.include?('/login')
        log('[everevo] ✅ ログイン済み')
        return
      end

      creds = ServiceConnection.credentials_for('everevo')
      raise '[everevo] メールアドレスが未設定です' if creds[:email].blank?

      page.fill('#email, input[name="_email"]', creds[:email])
      page.fill('#password, input[name="_password"]', creds[:password])
      page.click('#login_form button[type="submit"], button:has-text("ログイン")')
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      if page.url.include?('/login')
        raise '[everevo] ログイン失敗'
      end
      log("[everevo] ✅ ログイン完了 → #{page.url}")
    end

    def create_event(page, content, ef)
      log('[everevo] イベント作成ページへ移動...')
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      title_text = extract_title(ef, content, 100)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      # ===== イベント名 =====
      name_input = page.locator('.el-form-item.is-required input.el-input__inner').first
      if (name_input.visible?(timeout: 5000) rescue false)
        name_input.fill(title_text)
        log("[everevo] イベント名: #{title_text}")
      else
        # フォールバック
        page.locator('input').first.fill(title_text) rescue nil
      end

      # ===== 日時（Element UI DatePicker / TimePicker） =====
      fill_element_ui_dates(page, start_date, start_time, end_date, end_time)

      # 告知期間（今日〜イベント当日）
      today = Date.today.strftime('%Y-%m-%d')
      fill_element_ui_notice_dates(page, today, '00:00', start_date, start_time)

      # ===== 会場 =====
      place = ef['place'].presence || 'オンライン'
      place_input = page.locator('#place_name, input[placeholder*="武道館"]').first
      if (place_input.visible?(timeout: 3000) rescue false)
        place_input.fill(place)
        log("[everevo] 会場: #{place}")
      end

      # ===== カテゴリー（ビジネス=17） =====
      cat_select = page.locator('.el-select[placeholder*="カテゴリー"], .el-select').first
      if (cat_select.visible?(timeout: 3000) rescue false)
        cat_select.click
        page.wait_for_timeout(500)
        biz_option = page.locator('.el-select-dropdown__item:has-text("ビジネス")').first
        biz_option.click if (biz_option.visible?(timeout: 2000) rescue false)
        page.wait_for_timeout(500)
        # ドロップダウンを閉じる
        page.keyboard.press('Escape') rescue nil
        log('[everevo] カテゴリー: ビジネス')
      end

      # ===== 説明文（Summernote） =====
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight / 2)")
      page.wait_for_timeout(1000)
      plain_content = content.gsub(/<[^>]+>/, '').strip
      # 絵文字を除去（everevoは絵文字非対応）
      clean_content = plain_content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
                                   .gsub(/[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
      html_content = clean_content.split("\n").map { |l| "<p>#{l}</p>" }.join
      page.evaluate(<<~JS, arg: html_content)
        (html) => {
          if (typeof $ !== 'undefined' && $('#editor').length) {
            $('#editor').summernote('code', html);
          } else {
            const editor = document.querySelector('.note-editable, [contenteditable="true"]');
            if (editor) editor.innerHTML = html;
          }
        }
      JS
      log('[everevo] 説明文入力完了')

      # ===== チケット =====
      ticket_inputs = page.locator('input[placeholder*="入場券"], input[placeholder*="チケット"]')
      if (ticket_inputs.count > 0 rescue false)
        ticket_inputs.first.fill('参加チケット')
        log('[everevo] チケット名: 参加チケット')
      end

      price_input = page.locator('input[placeholder*="無料なら"]').first
      if (price_input.visible?(timeout: 2000) rescue false)
        price_input.fill('0')
        log('[everevo] 料金: 無料')
      end

      capacity = ef['capacity'].presence || '50'
      limit_input = page.locator('input[placeholder="100"]').first
      if (limit_input.visible?(timeout: 2000) rescue false)
        limit_input.fill(capacity)
        log("[everevo] 定員: #{capacity}")
      end

      # ===== 画像アップロード =====
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        file_input = page.locator('.el-upload input[type="file"]').first
        if (file_input.count > 0 rescue false)
          file_input.set_input_files(ef['imagePath'])
          page.wait_for_timeout(3000)
          log('[everevo] 画像アップロード完了')
        end
      end

      # ===== 保存 =====
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
      page.wait_for_timeout(1000)

      # 公開フラグ
      do_publish = ef.dig('publishSites', 'everevo')

      if do_publish
        # 公開保存
        page.evaluate(<<~JS)
          (() => {
            const app = document.querySelector('#app')?.__vue__;
            if (app && app.$children) {
              const form = app.$children.find(c => c.doPublish !== undefined);
              if (form) form.doPublish = true;
            }
          })()
        JS
        log('[everevo] 公開モードで保存...')
      end

      # ダイアログが出ていればOKを押す
      ok_btn = page.locator('.el-message-box .el-button--primary, button:has-text("OK")').first
      ok_btn.click if (ok_btn.visible?(timeout: 2000) rescue false)
      page.wait_for_timeout(500)

      save_btn = page.locator('button:has-text("保存する"), button.el-button--lg, button:has-text("保存"), button[type="submit"]').first
      if (save_btn.visible?(timeout: 5000) rescue false)
        save_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
        log("[everevo] ✅ 保存完了 → #{page.url}")
      else
        raise '[everevo] 保存ボタンが見つかりません'
      end

      log("[everevo] ✅ 処理完了 → #{page.url}")
    end

    def fill_element_ui_dates(page, start_date, start_time, end_date, end_time)
      # Vue.jsのElement UI DatePicker/TimePickerはJS経由で設定が最も確実
      page.evaluate(<<~JS, arg: { sd: start_date, st: start_time, ed: end_date, et: end_time })
        (d) => {
          const setNativeValue = (el, value) => {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
            setter.call(el, value);
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          };
          const dateInputs = document.querySelectorAll('.el-date-editor--date input');
          const timeInputs = document.querySelectorAll('.el-date-editor--time input');
          if (dateInputs[0]) setNativeValue(dateInputs[0], d.sd);
          if (timeInputs[0]) setNativeValue(timeInputs[0], d.st);
          if (dateInputs[1]) setNativeValue(dateInputs[1], d.ed);
          if (timeInputs[1]) setNativeValue(timeInputs[1], d.et);
        }
      JS
      log("[everevo] 日時: #{start_date} #{start_time} 〜 #{end_date} #{end_time}")
    end

    def fill_element_ui_notice_dates(page, start_date, start_time, end_date, end_time)
      page.evaluate(<<~JS, arg: { sd: start_date, st: start_time, ed: end_date, et: end_time })
        (d) => {
          const setNativeValue = (el, value) => {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
            setter.call(el, value);
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          };
          const dateInputs = document.querySelectorAll('.el-date-editor--date input');
          const timeInputs = document.querySelectorAll('.el-date-editor--time input');
          // 告知開始日・時間（3番目, 5番目）
          if (dateInputs[2]) setNativeValue(dateInputs[2], d.sd);
          if (timeInputs[2]) setNativeValue(timeInputs[2], d.st);
          // 告知終了日・時間（4番目, 6番目）
          if (dateInputs[3]) setNativeValue(dateInputs[3], d.ed);
          if (timeInputs[3]) setNativeValue(timeInputs[3], d.et);
        }
      JS
      log("[everevo] 告知期間: #{start_date} 〜 #{end_date}")
    end
  end
end
