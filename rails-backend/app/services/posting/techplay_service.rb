module Posting
  class TechplayService < BaseService
    AUTH_URL      = 'https://owner.techplay.jp/auth'
    DASHBOARD_URL = 'https://owner.techplay.jp/dashboard'
    EVENT_URL     = 'https://owner.techplay.jp/event'
    CREATE_URL    = 'https://owner.techplay.jp/event/create'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    # ===== ログイン =====
    def ensure_login(page)
      log('[TechPlay] ログインページへ移動...')
      page.goto(AUTH_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      if page.url.include?('dashboard') || page.url.include?('select_menu')
        log('[TechPlay] ✅ ログイン済み')
        return
      end

      page.fill('#email', ENV['TECHPLAY_EMAIL'].to_s)
      page.fill('#password', ENV['TECHPLAY_PASSWORD'].to_s)
      page.click("input[type='submit']")
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      current_url = page.url
      log("[TechPlay] ログイン後URL: #{current_url}")

      if current_url.include?('/auth') && !current_url.include?('select_menu')
        raise '[TechPlay] ログイン失敗'
      end

      log('[TechPlay] ✅ ログイン完了')
    end

    # ===== イベント作成 =====
    def create_event(page, content, ef)
      # /event ページへ移動して「新規作成」ボタンをクリック
      log('[TechPlay] イベント一覧ページへ移動...')
      page.goto(EVENT_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      new_btn = page.locator("a:has-text('新規作成')").first
      if (new_btn.visible?(timeout: 3000) rescue false)
        new_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
        log('[TechPlay] イベント作成ページへ遷移')
      else
        log('[TechPlay] 新規作成ボタン未検出、直接URLへ移動')
        page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
        page.wait_for_timeout(3000)
      end

      log("[TechPlay] 現在のURL: #{page.url}")

      # ----- タイトル -----
      title_text = extract_title(ef, content, 100)
      page.fill('#title', title_text)
      log("[TechPlay] タイトル入力: #{title_text}")

      # ----- 開催日時 (Vue datetimepicker) -----
      fill_datetime(page, ef)

      # ----- エリア: オンライン -----
      # area_types[] の最初のチェックボックスが「オンライン」
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        online_cb = page.locator("input[name='area_types[]']").first
        if (online_cb.visible?(timeout: 2000) rescue false)
          online_cb.check unless (online_cb.checked? rescue false)
          log('[TechPlay] エリア: オンラインをチェック')
        end
      end

      # ----- オンライン参加方法 (online_type) + Zoom URL -----
      zoom_url = ef['zoomUrl'].to_s
      if zoom_url.present? || place.include?('オンライン')
        # online_type を "link"（URLを設定する）に変更 → online_comment 欄が表示される
        page.evaluate(<<~JS)
          (() => {
            // ラジオボタン方式
            const radios = document.querySelectorAll('input[name="online_type"]');
            for (const r of radios) {
              if (r.value === 'link') {
                r.checked = true;
                r.dispatchEvent(new Event('change', { bubbles: true }));
                r.dispatchEvent(new Event('input', { bubbles: true }));
                return;
              }
            }
            // セレクト方式
            const sel = document.querySelector('select[name="online_type"]');
            if (sel) {
              sel.value = 'link';
              sel.dispatchEvent(new Event('change', { bubbles: true }));
            }
          })()
        JS
        page.wait_for_timeout(1000)
        log('[TechPlay] オンライン参加方法: URL設定（link）に変更')

        if zoom_url.present?
          zoom_text = "お時間になりましたら、下記URLよりご入室ください。\n#{zoom_url}"
          zoom_text += "\n\nミーティングID: #{ef['zoomId']}" if ef['zoomId'].present?
          zoom_text += "\nパスコード: #{ef['zoomPasscode']}" if ef['zoomPasscode'].present?

          # online_comment テキストエリアに入力
          online_field = page.locator("textarea[name='online_comment'], #online_comment, textarea[name*='online']").first
          if (online_field.visible?(timeout: 3000) rescue false)
            online_field.fill(zoom_text)
            log("[TechPlay] Zoom URL入力完了: #{zoom_url}")
          else
            # Vue reactivity 対応: JS で直接セット
            page.evaluate(<<~JS, arg: zoom_text)
              (text) => {
                const selectors = ['textarea[name="online_comment"]', '#online_comment', 'textarea[name*="online"]'];
                for (const sel of selectors) {
                  const el = document.querySelector(sel);
                  if (el) {
                    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set
                                || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
                    if (setter) setter.call(el, text);
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                    return true;
                  }
                }
                return false;
              }
            JS
            log("[TechPlay] Zoom URL入力完了（JS経由）")
          end
        end
      end

      # ----- 参加枠名 -----
      slot_name = place
      page.fill("input[name='attendTypes[0][name]']", slot_name)
      log("[TechPlay] 参加枠名入力: #{slot_name}")

      # ----- 定員数 -----
      capacity = ef['capacity'].presence || '50'
      cap_input = page.locator("input[name='attendTypes[0][capacity]']").first
      if (cap_input.visible?(timeout: 2000) rescue false)
        cap_input.fill('')
        cap_input.fill(capacity.to_s)
        log("[TechPlay] 定員数入力: #{capacity}")
      end

      # ----- 説明文（イベント内容） -----
      lines = content.split("\n")
      first_line = lines.first.to_s.gsub(/\A[#\s「『【]+/, '').gsub(/[】』」\s]+\z/, '').strip
      body_text = (first_line.present? && title_text.include?(first_line)) ? lines.drop(1).join("\n").lstrip : content

      # TechPlayの説明欄はtextareaまたはリッチエディタ
      desc_filled = false
      # textarea方式
      desc_area = page.locator('textarea[name="detail"], textarea#detail, textarea[name="description"]').first
      if (desc_area.visible?(timeout: 3000) rescue false)
        desc_area.fill(body_text)
        desc_filled = true
        log('[TechPlay] 説明文入力完了（textarea）')
      end
      # contenteditable方式
      unless desc_filled
        editor = page.locator('[contenteditable="true"]').first
        if (editor.visible?(timeout: 2000) rescue false)
          editor.click
          page.keyboard.type(body_text)
          desc_filled = true
          log('[TechPlay] 説明文入力完了（contenteditable）')
        end
      end
      # Vue tiptap/quill方式
      unless desc_filled
        page.evaluate(<<~JS, arg: body_text)
          (text) => {
            const editors = document.querySelectorAll('.ProseMirror, .ql-editor, .tiptap, [contenteditable]');
            for (const ed of editors) {
              if (ed.offsetHeight > 50) {
                ed.innerHTML = text.replace(/\\n/g, '<br>');
                ed.dispatchEvent(new Event('input', { bubbles: true }));
                return true;
              }
            }
            return false;
          }
        JS
        log('[TechPlay] 説明文入力完了（エディタ）')
      end

      # 申込形式・参加費はデフォルトのまま
      log('[TechPlay] 申込形式・参加費はデフォルト値を使用')

      # ----- 保存 -----
      log('[TechPlay] 保存ボタンをクリック...')
      save_btn = page.locator("button[type='submit']:has-text('保存')").first
      raise '[TechPlay] 保存ボタンが見つかりません' unless (save_btn.visible?(timeout: 3000) rescue false)

      save_btn.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)
      log("[TechPlay] ✅ 保存完了 → #{page.url}")

      # ----- 公開 -----
      publish = ef.dig('publishSites', 'TechPlay')
      if publish
        log('[TechPlay] 公開設定が有効 → 公開処理を実行')
        publish_event(page)
      else
        log('[TechPlay] 公開設定: 非公開（下書き保存のみ）')
      end

      log("[TechPlay] ✅ 処理完了 → #{page.url}")
    end

    # ===== 日時入力 (Vue datetimepicker) =====
    def fill_datetime(page, ef)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_date   = normalize_date(ef['endDate'].presence || start_date)
      end_time   = pad_time(ef['endTime'])

      # Vue datetimepicker: テキスト入力として値をセット
      # フォーマット: "YYYY/MM/DD HH:mm" が一般的
      start_formatted = "#{start_date.gsub('-', '/')} #{start_time}"
      end_formatted   = "#{end_date.gsub('-', '/')} #{end_time}"

      set_datetimepicker(page, '#v-datetimepicker-start', start_formatted, '開始')
      set_datetimepicker(page, '#v-datetimepicker-end', end_formatted, '終了')
    end

    def set_datetimepicker(page, selector, value, label)
      el = page.locator(selector).first
      return log("[TechPlay] ⚠️ #{label}日時欄が見つかりません") unless (el.visible?(timeout: 2000) rescue false)

      # input をクリックしてフォーカス
      el.click
      page.wait_for_timeout(500)

      # 既存値をクリアして入力（nativeInputValueSetterでVue reactivityをトリガー）
      js = <<~JS
        (args) => {
          var input = document.querySelector(args[0]);
          if (input) {
            var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
            nativeInputValueSetter.call(input, args[1]);
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
            input.dispatchEvent(new Event('blur', { bubbles: true }));
          }
        }
      JS
      page.evaluate_handle(js, arg: [selector, value])

      page.wait_for_timeout(500)
      # カレンダーポップアップが開いていれば閉じる
      page.keyboard.press('Escape') rescue nil
      page.wait_for_timeout(300)

      log("[TechPlay] #{label}日時入力: #{value}")
    end

    # ===== 公開 =====
    def publish_event(page)
      # 保存後のページで公開ボタンを探す
      publish_btn = nil
      ['公開する', '公開'].each do |text|
        btn = page.locator("button:has-text('#{text}'), a:has-text('#{text}')").first
        if (btn.visible?(timeout: 2000) rescue false)
          publish_btn = btn
          break
        end
      end

      if publish_btn
        publish_btn.click
        page.wait_for_timeout(2000)

        # 確認ダイアログ
        ['はい', 'OK', '公開する', '確認'].each do |text|
          confirm = page.locator("button:has-text('#{text}')").first
          if (confirm.visible?(timeout: 2000) rescue false)
            confirm.click
            page.wait_for_timeout(2000)
            break
          end
        end

        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        log("[TechPlay] ✅ 公開完了 → #{page.url}")
      else
        log('[TechPlay] ⚠️ 公開ボタンが見つかりません')
      end
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      # TechPlayは限定公開→下書きにしてから削除扱い
      # editページへ遷移
      edit_url = event_url.sub(/\/edit\/?$/, '') + '/edit'
      page.goto(edit_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[TechPlay] イベント削除中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil

      # ページ下部にスクロールして削除ボタンを探す
      page.evaluate('() => window.scrollTo(0, document.body.scrollHeight)')
      page.wait_for_timeout(1000)

      del_btn = page.locator('button:has-text("削除"), a:has-text("削除"), button:has-text("Delete")').first
      if (del_btn.visible?(timeout: 3000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[TechPlay] ✅ イベント削除完了')
      else
        # 削除がなければ「限定公開にする」で非公開に
        limited = page.locator('button:has-text("限定公開にする")').first
        if (limited.visible?(timeout: 3000) rescue false)
          limited.click
          page.wait_for_timeout(2000)
          confirm = page.locator('button:has-text("OK"), button:has-text("はい"), button:has-text("限定公開")').first
          confirm.click if (confirm.visible?(timeout: 3000) rescue false)
          page.wait_for_timeout(3000)
          log('[TechPlay] ✅ 限定公開（非公開）に変更完了')
        else
          raise '[TechPlay] 削除/非公開ボタンが見つかりません'
        end
      end
    end

    def perform_cancel(page, event_url)
      # TechPlayは「限定公開にする」で実質中止
      perform_delete(page, event_url)
    end
  end
end
