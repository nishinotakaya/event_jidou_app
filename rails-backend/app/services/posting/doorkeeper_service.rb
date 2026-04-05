module Posting
  class DoorkeeperService < BaseService
    LOGIN_URL  = 'https://manage.doorkeeper.jp/user/sign_in'
    MANAGE_URL = 'https://manage.doorkeeper.jp'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    # ===== ログイン =====
    def ensure_login(page)
      log('[Doorkeeper] ログインページへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      # ログイン済みならスキップ
      unless page.url.include?('/sign_in')
        log('[Doorkeeper] ✅ ログイン済み')
        return
      end

      creds = ServiceConnection.credentials_for('doorkeeper')
      raise '[Doorkeeper] メールアドレスが未設定です' if creds[:email].blank?

      # fetch POST方式でログイン（manage側セッション維持のため redirect:manual が必須）
      log('[Doorkeeper] fetch POSTでログイン...')
      page.evaluate(<<~JS, arg: { email: creds[:email], password: creds[:password] })
        async (creds) => {
          const token = document.querySelector('meta[name="csrf-token"]')?.content ||
                       document.querySelector('input[name="authenticity_token"]')?.value || '';
          const params = new URLSearchParams();
          params.append('authenticity_token', token);
          params.append('user[email]', creds.email);
          params.append('user[password]', creds.password);
          params.append('user[remember_me]', '1');
          await fetch('/user/sign_in', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: params.toString(),
            redirect: 'manual',
            credentials: 'same-origin'
          });
        }
      JS
      page.goto("#{MANAGE_URL}/groups", waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # www.doorkeeper.jpにリダイレクトされた場合、manage側に戻る
      if page.url.include?('www.doorkeeper.jp')
        page.goto("#{MANAGE_URL}/groups", waitUntil: 'domcontentloaded', timeout: 30_000)
        page.wait_for_timeout(3000)
      end

      if page.url.include?('/sign_in')
        raise '[Doorkeeper] ログイン失敗'
      end

      log("[Doorkeeper] ✅ ログイン完了 → #{page.url}")
    end

    # ===== イベント作成 =====
    def create_event(page, content, ef)
      group_name = AppSetting.get('doorkeeper_group_name').presence || ENV['DOORKEEPER_GROUP_NAME'].to_s
      raise '[Doorkeeper] DOORKEEPER_GROUP_NAME が未設定です（AppSetting or ENV）' if group_name.blank?

      create_url = "#{MANAGE_URL}/groups/#{group_name}/events/new"
      log("[Doorkeeper] イベント作成ページへ移動: #{create_url}")
      page.goto(create_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # ----- タイトル -----
      title_text = extract_title(ef, content, 100)
      title_input = page.locator('#event_title_ja,input[name="event[title_ja]"],input[name="event[title]"],input#event_title').first
      if (title_input.visible?(timeout: 5000) rescue false)
        title_input.fill(title_text)
        log("[Doorkeeper] タイトル入力: #{title_text}")
      else
        raise '[Doorkeeper] タイトル入力欄が見つかりません'
      end

      # ----- 開催日時（date input + time select） -----
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      # 開始日
      start_date_input = page.locator('#event_starts_at_date,input[name="event[starts_at_date]"]').first
      if (start_date_input.visible?(timeout: 2000) rescue false)
        start_date_input.fill(start_date)
        page.keyboard.press('Escape') rescue nil
        log("[Doorkeeper] 開始日: #{start_date}")
      end

      # 開始時（select）
      sh, sm = start_time.split(':')
      page.locator('#event_starts_at_time_4i').first.select_option(value: sh.to_i.to_s) rescue nil
      page.locator('#event_starts_at_time_5i').first.select_option(value: (sm.to_i / 5 * 5).to_s.rjust(2, '0')) rescue nil
      log("[Doorkeeper] 開始時刻: #{start_time}")

      # 終了日
      end_date_input = page.locator('#event_ends_at_date,input[name="event[ends_at_date]"]').first
      if (end_date_input.visible?(timeout: 2000) rescue false)
        end_date_input.fill(end_date)
        page.keyboard.press('Escape') rescue nil
        log("[Doorkeeper] 終了日: #{end_date}")
      end

      # 終了時（select）
      eh, em = end_time.split(':')
      page.locator('#event_ends_at_time_4i').first.select_option(value: eh.to_i.to_s) rescue nil
      page.locator('#event_ends_at_time_5i').first.select_option(value: (em.to_i / 5 * 5).to_s.rjust(2, '0')) rescue nil
      log("[Doorkeeper] 終了時刻: #{end_time}")

      # ----- 日付のhidden fields更新（年/月/日を同期） -----
      s_year, s_month, s_day = start_date.split('-')
      e_year, e_month, e_day = end_date.split('-')
      page.evaluate(<<~JS, arg: { sy: s_year, sm: s_month.to_i.to_s, sd: s_day.to_i.to_s, ey: e_year, em: e_month.to_i.to_s, ed: e_day.to_i.to_s })
        (d) => {
          const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
          set('event_starts_at_time_1i', d.sy);
          set('event_starts_at_time_2i', d.sm);
          set('event_starts_at_time_3i', d.sd);
          set('event_ends_at_time_1i', d.ey);
          set('event_ends_at_time_2i', d.em);
          set('event_ends_at_time_3i', d.ed);
        }
      JS
      log('[Doorkeeper] 日付hidden fields更新')

      # ----- 場所（オンライン/会場 radio） -----
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        online_radio = page.locator('#event_attendance_type_online').first
        online_radio.check if (online_radio.visible?(timeout: 2000) rescue false)
        page.wait_for_timeout(1000)
        log('[Doorkeeper] 場所: オンライン開催を選択')

        # オンラインイベントURL（required）
        zoom_url = ef['zoomUrl'].presence || 'https://us02web.zoom.us/j/example'
        online_url_input = page.locator('#event_online_event_url').first
        if (online_url_input.visible?(timeout: 3000) rescue false)
          online_url_input.fill(zoom_url)
          log("[Doorkeeper] オンラインURL入力: #{zoom_url}")
        end
      else
        inperson_radio = page.locator('#event_attendance_type_in_person').first
        inperson_radio.check if (inperson_radio.visible?(timeout: 2000) rescue false)
        page.wait_for_timeout(1000)
        log('[Doorkeeper] 場所: 会場開催を選択')
      end

      # ----- 説明文 -----
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
      page.wait_for_timeout(1000)
      desc_area = page.locator('#event_description_ja,textarea[name="event[description_ja]"]').first
      if (desc_area.visible?(timeout: 3000) rescue false)
        desc_area.fill(content)
        log('[Doorkeeper] 説明文入力完了')
      else
        page.evaluate(<<~JS, arg: content)
          (text) => {
            const ta = document.getElementById('event_description_ja');
            if (ta) { ta.value = text; ta.dispatchEvent(new Event('input', { bubbles: true })); }
          }
        JS
        log('[Doorkeeper] 説明文入力完了（JS経由）')
      end

      # ----- チケット設定（チケット名は必須） -----
      ticket_desc = page.locator('#event_ticket_types_attributes_0_description_ja').first
      page.evaluate(<<~JS)
        (() => {
          const el = document.getElementById('event_ticket_types_attributes_0_description_ja');
          if (el) { el.value = 'オンラインチケット'; el.dispatchEvent(new Event('input', { bubbles: true })); }
          const free = document.getElementById('event_ticket_types_attributes_0_admission_type_free');
          if (free) free.checked = true;
        })()
      JS
      log('[Doorkeeper] チケット設定: オンラインチケット（無料）')

      # ----- 定員 -----
      capacity = ef['capacity'].presence || '50'
      page.evaluate(<<~JS, arg: capacity.to_s)
        (cap) => {
          const el = document.getElementById('event_ticket_types_attributes_0_ticket_limit');
          if (el) { el.value = cap; el.dispatchEvent(new Event('input', { bubbles: true })); }
        }
      JS
      log("[Doorkeeper] 定員: #{capacity}")

      page.evaluate("() => window.scrollTo(0, 0)")
      page.wait_for_timeout(500)

      # ----- 保存 -----
      log('[Doorkeeper] 保存ボタンをクリック...')
      save_btn = page.locator("input[type='submit'],button[type='submit']").last
      raise '[Doorkeeper] 保存ボタンが見つかりません' unless (save_btn.visible?(timeout: 3000) rescue false)

      save_btn.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)
      log("[Doorkeeper] ✅ 保存完了 → #{page.url}")

      # ----- 公開 -----
      if ef.dig('publishSites', 'Doorkeeper')
        log('[Doorkeeper] 公開処理を実行...')
        publish_event(page)
      else
        log('[Doorkeeper] 公開設定: 非公開（下書き保存のみ）')
      end

      log("[Doorkeeper] ✅ 処理完了 → #{page.url}")
    end

    # ===== 日時入力ヘルパー =====
    def fill_datetime_field(page, name, value, label)
      input = page.locator("input[name='#{name}']").first
      if (input.visible?(timeout: 2000) rescue false)
        input.click
        page.wait_for_timeout(300)
        # nativeInputValueSetter でフレームワーク対応
        page.evaluate(<<~JS, arg: ["input[name='#{name}']", value])
          (args) => {
            const el = document.querySelector(args[0]);
            if (el) {
              const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
              setter.call(el, args[1]);
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }
          }
        JS
        page.keyboard.press('Escape') rescue nil
        page.wait_for_timeout(300)
        log("[Doorkeeper] #{label}日時入力: #{value}")
      else
        log("[Doorkeeper] ⚠️ #{label}日時欄が見つかりません")
      end
    end

    # ===== 公開 =====
    def publish_event(page)
      publish_btn = nil
      ['公開する', '公開', 'Publish'].each do |text|
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
        ['はい', 'OK', '公開する', 'Publish', '確認'].each do |text|
          confirm = page.locator("button:has-text('#{text}')").first
          if (confirm.visible?(timeout: 2000) rescue false)
            confirm.click
            page.wait_for_timeout(2000)
            break
          end
        end

        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        log("[Doorkeeper] ✅ 公開完了 → #{page.url}")
      else
        log('[Doorkeeper] ⚠️ 公開ボタンが見つかりません')
      end
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[Doorkeeper] 削除ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      del_btn = page.locator('a:has-text("削除"), button:has-text("削除"), a:has-text("Delete"), button:has-text("Delete")').first
      if (del_btn.visible?(timeout: 5000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes"), button:has-text("Delete")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[Doorkeeper] ✅ イベント削除完了')
      else
        raise '[Doorkeeper] 削除ボタンが見つかりません'
      end
    end

    def perform_cancel(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[Doorkeeper] 中止処理中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      cancel_btn = page.locator('a:has-text("中止"), button:has-text("中止"), a:has-text("キャンセル"), button:has-text("Cancel"), a:has-text("Cancel")').first
      if (cancel_btn.visible?(timeout: 5000) rescue false)
        cancel_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("中止"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[Doorkeeper] ✅ イベント中止完了')
      else
        raise '[Doorkeeper] 中止ボタンが見つかりません'
      end
    end
  end
end
