require 'net/http'
require 'uri'
require 'json'

module Posting
  class TunagateService < BaseService
    SIGN_IN_URL = 'https://tunagate.com/users/sign_in?ifx=yBrPZyXgNqee6MeA'
    MENU_URL    = 'https://tunagate.com/menu'
    SESSION_PATH = Rails.root.join('tmp', 'tunagate_session.json').to_s

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    def ensure_login(page)
      log('[つなゲート] ログイン確認...')

      page.goto(MENU_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # ログイン済みチェック（つなゲートのメニューページが表示されればOK）
      if page.url.include?('tunagate.com') && !page.url.include?('sign_in') && !page.url.include?('accounts.google')
        log('[つなゲート] ✅ ログイン済み')
        return
      end

      # Googleログイン試行
      log('[つなゲート] Googleログイン開始...')
      page.goto(SIGN_IN_URL, waitUntil: 'networkidle', timeout: 30_000)
      page.wait_for_timeout(2000)

      google_btn = page.locator("a:has-text('Google')").first
      raise '[つなゲート] Googleログインボタンが見つかりません' unless (google_btn.visible?(timeout: 3000) rescue false)
      google_btn.click
      page.wait_for_timeout(5000)

      if page.url.include?('accounts.google.com')
        log('[つなゲート] Googleアカウント認証中...')

        # メール入力
        email_input = page.locator("input[type='email']").first
        if (email_input.visible?(timeout: 5000) rescue false)
          email_input.fill(ENV['GOOGLE_EMAIL'].to_s)
          page.locator('#identifierNext').first.click
          page.wait_for_timeout(4000)
          log('[つなゲート] メール入力完了')

          # パスワード入力
          pass_input = page.locator("input[type='password']").first
          if (pass_input.visible?(timeout: 5000) rescue false)
            pass_input.fill(ENV['GOOGLE_PASSWORD'].to_s)
            page.locator('#passwordNext').first.click
            page.wait_for_timeout(5000)
            log('[つなゲート] パスワード入力完了')
          end
        end

        # 2FA対応
        if page.url.include?('challenge')
          log('[つなゲート] 2段階認証...')
          tap_option = page.locator('[data-challengetype="39"]').first
          if (tap_option.visible?(timeout: 3000) rescue false)
            tap_option.click
            page.wait_for_timeout(2000)
            log('[つなゲート] 📱 スマートフォンで「はい」をタップしてください...')
            60.times do |i|
              page.wait_for_timeout(2000)
              break unless page.url.include?('challenge')
              log("[つなゲート] ⏳ 承認待ち... (#{(i + 1) * 2}秒)") if i % 10 == 9
            end
          end
        end

        # OAuth同意画面の「次へ」クリック
        page.wait_for_timeout(2000)
        if page.url.include?('consent') || page.url.include?('oauth/id')
          log('[つなゲート] OAuth同意画面...')

          # Googleのローディングオーバーレイ（dKGsO等）が消えるのを待つ
          15.times do
            overlay_visible = page.evaluate(<<~'JS') rescue false
              (() => {
                const els = document.querySelectorAll('div[jsname="OQ2Y6"], div.dKGsO, [role="progressbar"]');
                for (const el of els) {
                  if (el.offsetParent !== null) {
                    const r = el.getBoundingClientRect();
                    if (r.width > 50 && r.height > 50) return true;
                  }
                }
                return false;
              })()
            JS
            break unless overlay_visible
            page.wait_for_timeout(1000)
          end
          page.wait_for_timeout(1500)

          next_btn = page.locator('button:has-text("次へ"), button:has-text("Continue"), button:has-text("許可")').first
          if (next_btn.visible?(timeout: 5000) rescue false)
            begin
              next_btn.click(timeout: 5_000)
            rescue
              log('[つなゲート] 通常クリック失敗 → force click')
              next_btn.click(force: true) rescue nil
            end
            page.wait_for_timeout(8000)
            log('[つなゲート] 「次へ」クリック完了')
          end
        end

        # つなゲートへのリダイレクト待機
        10.times do
          page.wait_for_timeout(2000)
          current = page.url
          break if current.start_with?('https://tunagate.com') && !current.include?('sign_in')
          # Google rejected 検出
          if current.include?('signin/rejected')
            raise "[つなゲート] Googleログイン拒否。接続管理から「ブラウザログイン」でログインしてください。"
          end
        end
      end

      page.wait_for_timeout(2000)
      current = page.url
      if current.start_with?('https://tunagate.com') && !current.include?('sign_in')
        # セッション保存
        page.context.storage_state(path: SESSION_PATH) rescue nil
        log("[つなゲート] ✅ ログイン成功 → #{current}")
      else
        raise "[つなゲート] ログイン失敗 (URL: #{current[0, 80]})。接続管理から「ブラウザログイン」でログインしてください。"
      end
    end

    def create_event(page, content, ef)
      # サークルIDを取得（AppSettingまたはデフォルト）
      circle_id = AppSetting.get('tunagate_circle_id').presence || '220600'
      create_url = "https://tunagate.com/events/new/#{circle_id}"
      log("[つなゲート] イベント作成ページへ移動: #{create_url}")
      page.goto(create_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      if page.url.include?('sign_in')
        raise '[つなゲート] ログインが必要です'
      end

      log("[つなゲート] イベント作成ページ → #{page.url}")
      dump_form(page)

      title = extract_title(ef, content, 100)

      # つなゲートはタイトルもtextarea（1番目=タイトル、2番目=説明）
      textareas = page.locator('textarea').all.select { |el| (el.visible?(timeout: 500) rescue false) }
      if textareas.length >= 2
        textareas[0].fill(title)
        log("[つなゲート] イベント名: #{title[0..40]}")
        textareas[1].fill(content)
        log('[つなゲート] 説明入力完了')
      elsif textareas.length == 1
        textareas[0].fill(content)
        log('[つなゲート] 説明入力完了（タイトル欄なし）')
        fill_first_empty_input(page, title, 'イベント名')
      else
        fill_first_empty_input(page, title, 'イベント名')
        fill_first_textarea(page, content)
      end

      # チケット追加
      ticket = page.locator("button:has-text('チケット'), a:has-text('チケット')").first
      if (ticket.visible?(timeout: 2000) rescue false)
        ticket.click
        page.wait_for_timeout(2000)
        log('[つなゲート] チケット追加')
      end

      # 日時
      fill_datetime(page, ef)

      # 開催場所
      place = ef['place'].presence || 'オンライン'
      fill_by_label(page, '開催場所', place) || fill_by_label(page, '場所', place)

      # 募集人数
      capacity = ef['capacity'].presence || '50'
      fill_by_label(page, '募集人数', capacity) || fill_by_label(page, '定員', capacity)

      # 公開/下書き
      if ef.dig('publishSites', 'つなゲート')
        click_btn(page, '公開')
      else
        click_btn(page, '下書き') || click_btn(page, '保存')
      end

      page.wait_for_timeout(3000)

      # イベントURLを取得（ページ内のリンクから探す）
      event_url = page.evaluate(<<~JS) rescue nil
        () => {
          const links = [...document.querySelectorAll('a[href*="/events/"]')];
          const match = links.find(a => /circle\/\\d+\/events\/\\d+/.test(a.href));
          return match ? match.href : null;
        }
      JS
      event_url ||= page.url
      log("[つなゲート] ✅ 完了 → #{event_url}")
    end

    # --- helpers ---

    def fill_first_empty_input(page, value, label)
      page.locator("input[type='text'], input:not([type])").all.each do |el|
        next unless (el.visible?(timeout: 500) rescue false)
        next unless (el.input_value.to_s.strip.empty? rescue true)
        el.fill(value)
        log("[つなゲート] #{label}: #{value[0..40]}")
        return
      end
      log("[つなゲート] ⚠️ #{label}欄が見つかりません")
    end

    def fill_first_textarea(page, value)
      page.locator('textarea').all.each do |el|
        next unless (el.visible?(timeout: 500) rescue false)
        el.fill(value)
        log('[つなゲート] 説明入力完了')
        return
      end
      log('[つなゲート] ⚠️ 説明欄が見つかりません')
    end

    def fill_datetime(page, ef)
      date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      stime = pad_time(ef['startTime'])
      etime = pad_time(ef['endTime'])

      page.locator("input[type='date']").all.each do |el|
        next unless (el.visible?(timeout: 500) rescue false)
        el.fill(date); log("[つなゲート] 日付: #{date}"); break
      end

      times = page.locator("input[type='time']").all.select { |e| (e.visible?(timeout: 500) rescue false) }
      times[0]&.fill(stime)
      times[1]&.fill(etime)
      log("[つなゲート] 時刻: #{stime} - #{etime}") if times.any?
    end

    def fill_by_label(page, label, value)
      page.evaluate_handle(<<~JS, arg: [label, value])
        (args) => {
          const els = Array.from(document.querySelectorAll('label, th, dt, div, span'));
          const t = els.find(el => el.childElementCount === 0 && el.textContent.trim().includes(args[0]));
          if (!t) return false;
          const c = t.closest('div, tr, dl, fieldset') || t.parentElement;
          if (!c) return false;
          const input = c.querySelector('input, textarea, select');
          if (!input || !input.offsetParent) return false;
          Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set.call(input, args[1]);
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }
      JS
      true
    rescue
      false
    end

    def click_btn(page, text)
      btn = page.locator("button:has-text('#{text}'), a:has-text('#{text}')").first
      return false unless (btn.visible?(timeout: 2000) rescue false)
      btn.click; page.wait_for_timeout(2000); log("[つなゲート] 「#{text}」クリック"); true
    end

    def dump_form(page)
      fields = page.evaluate('JSON.stringify(Array.from(document.querySelectorAll("input, textarea, select, button")).filter(function(el){return el.offsetParent!==null}).slice(0,25).map(function(el){return {tag:el.tagName,type:el.type||"",name:el.name||"",ph:el.placeholder||"",text:(el.textContent||"").trim().substring(0,30)}}))')
      JSON.parse(fields).each { |f| log("  [#{f['tag']}] name=#{f['name']} type=#{f['type']} ph=#{f['ph']} text=#{f['text']}") }
    rescue => e
      log("  [dump] #{e.message}")
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[つなゲート] 削除ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      del_btn = page.locator('a:has-text("削除"), button:has-text("削除"), a:has-text("Delete"), button:has-text("Delete")').first
      if (del_btn.visible?(timeout: 5000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes"), button:has-text("Delete")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[つなゲート] ✅ イベント削除完了')
      else
        raise '[つなゲート] 削除ボタンが見つかりません'
      end
    end

    def perform_cancel(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[つなゲート] 中止処理中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      cancel_btn = page.locator('a:has-text("中止"), button:has-text("中止"), a:has-text("キャンセル"), button:has-text("Cancel"), a:has-text("Cancel")').first
      if (cancel_btn.visible?(timeout: 5000) rescue false)
        cancel_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("中止"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[つなゲート] ✅ イベント中止完了')
      else
        raise '[つなゲート] 中止ボタンが見つかりません'
      end
    end
  end
end
