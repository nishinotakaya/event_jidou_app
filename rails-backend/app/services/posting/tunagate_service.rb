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

      # セッションファイルがあれば使用（PostJobで設定済み）
      page.goto(MENU_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      unless page.url.include?('sign_in')
        log('[つなゲート] ✅ ログイン済み')
        return
      end

      # Googleログイン試行
      log('[つなゲート] Googleログイン...')
      page.goto(SIGN_IN_URL, waitUntil: 'networkidle', timeout: 30_000)
      page.wait_for_timeout(2000)

      google_btn = page.locator("a:has-text('Google')").first
      raise '[つなゲート] Googleログインボタンが見つかりません' unless (google_btn.visible?(timeout: 3000) rescue false)
      google_btn.click
      page.wait_for_timeout(5000)

      # Googleアカウント画面
      if page.url.include?('accounts.google.com')
        log('[つなゲート] Googleアカウント認証中...')
        # メール入力
        email_input = page.locator("input[type='email']").first
        if (email_input.visible?(timeout: 5000) rescue false)
          email_input.fill(ENV['GOOGLE_EMAIL'].to_s)
          page.wait_for_timeout(1000)
          page.locator('#identifierNext').first.click rescue nil
          page.wait_for_timeout(3000)

          # パスワード
          pass_input = page.locator("input[type='password']").first
          if (pass_input.visible?(timeout: 5000) rescue false)
            pass_input.fill(ENV['GOOGLE_PASSWORD'].to_s)
            page.wait_for_timeout(1000)
            page.locator('#passwordNext').first.click rescue nil
          end
        end

        # リダイレクト待機（最大60秒）
        30.times do
          sleep 2
          break if page.url.include?('tunagate.com') && !page.url.include?('sign_in')
        end
      end

      page.wait_for_timeout(2000)
      if page.url.include?('tunagate.com') && !page.url.include?('sign_in')
        log("[つなゲート] ✅ ログイン成功")
      else
        raise "[つなゲート] ログイン失敗。告知アプリの接続管理から「🌐 ログイン」でブラウザログインしてください。"
      end
    end

    def create_event(page, content, ef)
      log("[つなゲート] メニュー: #{page.url}")

      create_btn = page.locator("a:has-text('イベント作成'), button:has-text('イベント作成')").first
      raise '[つなゲート] イベント作成ボタンが見つかりません' unless (create_btn.visible?(timeout: 5000) rescue false)

      create_btn.click
      page.wait_for_timeout(3000)
      log('[つなゲート] イベント作成ページ')
      dump_form(page)

      # 新規サークルで追加
      new_circle = page.locator("text=新規サークル").first
      if (new_circle.visible?(timeout: 3000) rescue false)
        new_circle.click
        page.wait_for_timeout(2000)
        log('[つなゲート] 新規サークルで追加')
        dump_form(page)
      end

      # イベント名（最初の空のテキストinput）
      title = extract_title(ef, content, 100)
      fill_first_empty_input(page, title, 'イベント名')

      # イベントの説明（textarea）
      fill_first_textarea(page, content)

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
      log("[つなゲート] ✅ 完了 → #{page.url}")
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
  end
end
