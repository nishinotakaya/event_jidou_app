class ZoomService
  SIGN_IN_URL  = 'https://zoom.us/signin'
  MEETINGS_URL = 'https://zoom.us/meeting'
  SCHEDULE_URL = 'https://zoom.us/meeting/schedule'

  def initialize(&log_callback)
    @log = log_callback || ->(_msg) {}
  end

  # Returns { zoom_url:, meeting_id:, passcode: }
  def create_meeting(page, title:, start_date:, start_time:, duration_minutes: 120)
    login(page)
    schedule_meeting(page, title: title, start_date: start_date, start_time: start_time, duration_minutes: duration_minutes)
    extract_meeting_info(page)
  end

  private

  def log(msg)
    @log.call(msg.to_s)
  end

  # ===== LOGIN =====
  def login(page)
    log("[Zoom] ミーティングページにアクセスしてログイン状態を確認中...")
    page.goto(MEETINGS_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
    page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
    page.wait_for_timeout(2000)

    unless page.url.include?('/signin') || page.url.include?('/login')
      log("[Zoom] ✅ セッション有効 - ログイン済み")
      return
    end

    log("[Zoom] セッションが切れています。ログイン中...")

    # ServiceConnectionから取得、なければENVフォールバック
    zoom_conn = ServiceConnection.find_by(service_name: 'zoom')
    email    = zoom_conn&.email.presence || ENV['ZOOM_EMAIL'].to_s
    password = zoom_conn&.password_field.presence || ENV['ZOOM_PASSWORD'].to_s
    raise 'ZOOM_EMAIL が未設定です' if email.blank?
    raise 'ZOOM_PASSWORD が未設定です' if password.blank?

    log("[Zoom] メールアドレスを入力中...")
    email_input = page.locator('input[type="email"], input[name="email"], #email').first
    email_input.wait_for(state: 'visible', timeout: 10_000)
    email_input.fill(email)

    next_btn = page.locator('button:has-text("次へ"), button:has-text("Next"), button[type="submit"]').first
    next_btn.click
    page.wait_for_timeout(2000)

    log("[Zoom] パスワードを入力中...")
    pass_input = page.locator('input[type="password"], input[name="password"], #password').first
    pass_input.wait_for(state: 'visible', timeout: 10_000)
    pass_input.fill(password)

    # サインインボタン前にCAPTCHAがある場合
    solve_captcha_if_present(page)

    signin_btn = page.locator('button:has-text("サインイン"), button:has-text("Sign In"), button:has-text("ログイン"), button[type="submit"]').first
    signin_btn.click
    page.wait_for_timeout(5000)
    page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil

    # サインイン後にCAPTCHAが表示される場合（最大2回リトライ）
    2.times do |attempt|
      break unless page.url.include?('/signin') || page.url.include?('/login')

      log("[Zoom] ログインページに留まっています（試行#{attempt + 1}）— CAPTCHA確認中...")
      page.screenshot(path: Rails.root.join('tmp', "zoom_captcha_attempt_#{attempt}.png").to_s) rescue nil

      solved = solve_captcha_if_present(page)
      if solved
        # CAPTCHA解決後に再度サインインボタンを押す
        page.wait_for_timeout(1000)
        begin
          signin_btn2 = page.locator('button:has-text("サインイン"), button:has-text("Sign In"), button:has-text("ログイン"), button[type="submit"]').first
          signin_btn2.click
          page.wait_for_timeout(5000)
          page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
        rescue => e
          log("[Zoom] 再サインインボタン押下失敗: #{e.message}")
        end
      else
        log("[Zoom] CAPTCHAが検出されませんでした")
        break
      end
    end

    if page.url.include?('/signin') || page.url.include?('/login')
      # スクリーンショット保存
      page.screenshot(path: Rails.root.join('tmp', 'zoom_login_failed.png').to_s) rescue nil
      error_text = page.evaluate("document.querySelector('.error-message, [role=\"alert\"]')?.textContent?.trim() || ''") rescue ''
      page_text = page.evaluate("document.body.innerText.substring(0, 500)") rescue ''
      log("[Zoom] ページテキスト: #{page_text}")
      raise "Zoomログイン失敗: #{error_text.presence || 'ログインページから遷移できませんでした'}"
    end

    log("[Zoom] ✅ ログイン完了")
  end

  # ===== CAPTCHA解決（2CAPTCHA API）=====
  def solve_captcha_if_present(page)
    api_key = ENV['API2CAPTCHA_KEY'].to_s
    return if api_key.blank?

    captcha_info = page.evaluate(<<~'JS')
      (() => {
        // reCAPTCHA v2 visible
        const recaptcha = document.querySelector('.g-recaptcha, [data-sitekey]');
        if (recaptcha) {
          return { type: 'recaptcha_v2', sitekey: recaptcha.dataset.sitekey };
        }
        // reCAPTCHA v2 invisible / v3 — script タグまたはページテキストから検出
        const scripts = [...document.querySelectorAll('script[src*="recaptcha"]')];
        const bodyText = document.body.innerText || '';
        const hasRecaptchaText = bodyText.includes('reCAPTCHA') || bodyText.includes('recaptcha');
        if (scripts.length > 0 || hasRecaptchaText) {
          // data-sitekey を探す
          let sitekey = document.querySelector('[data-sitekey]')?.dataset?.sitekey || '';
          // グローバル変数から探す
          if (!sitekey && typeof gRecaptchaInvisible !== 'undefined') sitekey = gRecaptchaInvisible;
          if (!sitekey && typeof gRecaptchaVisible !== 'undefined') sitekey = gRecaptchaVisible;
          // scriptタグのrender パラメータから探す
          if (!sitekey) {
            for (const s of scripts) {
              const match = (s.src || '').match(/render=([^&]+)/);
              if (match) { sitekey = match[1]; break; }
            }
          }
          // Zoom既知のサイトキー（フォールバック）
          if (!sitekey) sitekey = '6LdZ7KgaAAAAACd71H_lz76FwfcJpc4OQ1J7MDWA';
          if (sitekey) return { type: 'recaptcha_v2_invisible', sitekey };
        }
        // hCaptcha
        const hcaptcha = document.querySelector('.h-captcha, [data-hcaptcha-sitekey]');
        if (hcaptcha) {
          return { type: 'hcaptcha', sitekey: hcaptcha.dataset.sitekey || hcaptcha.dataset.hcaptchaSitekey };
        }
        // Cloudflare Turnstile
        const turnstile = document.querySelector('.cf-turnstile');
        if (turnstile) {
          return { type: 'turnstile', sitekey: turnstile.dataset.sitekey };
        }
        return { type: 'none' };
      })()
    JS

    if captcha_info['type'] == 'none'
      log("[Zoom] CAPTCHAなし")
      return false
    end
    log("[Zoom] CAPTCHA検出: #{captcha_info['type']} — 2CAPTCHAで解決中...")

    sitekey  = captcha_info['sitekey'].to_s
    page_url = page.url

    case captcha_info['type']
    when 'recaptcha_v2_invisible'
      token = solve_with_2captcha(api_key, method: 'userrecaptcha', googlekey: sitekey, pageurl: page_url, invisible: 1)
      if token
        page.evaluate(<<~JS, arg: token)
          (token) => {
            // g-recaptcha-response に設定
            document.querySelectorAll('[name="g-recaptcha-response"], #g-recaptcha-response').forEach(el => {
              el.style.display = 'block';
              el.value = token;
            });
            // コールバック実行
            if (typeof ___grecaptcha_cfg !== 'undefined') {
              const clients = ___grecaptcha_cfg.clients;
              for (const key in clients) {
                const client = clients[key];
                const traverse = (obj) => {
                  if (!obj || typeof obj !== 'object') return;
                  for (const k in obj) {
                    if (obj[k] && typeof obj[k].callback === 'function') {
                      obj[k].callback(token);
                      return;
                    }
                    if (typeof obj[k] === 'object') traverse(obj[k]);
                  }
                };
                traverse(client);
              }
            }
          }
        JS
        log("[Zoom] ✅ reCAPTCHA invisible 解決完了")
      end

    when 'recaptcha_v2'
      token = solve_with_2captcha(api_key, method: 'userrecaptcha', googlekey: sitekey, pageurl: page_url)
      if token
        page.evaluate(<<~JS, arg: token)
          (token) => {
            const textarea = document.getElementById('g-recaptcha-response') || document.querySelector('[name="g-recaptcha-response"]');
            if (textarea) { textarea.style.display = 'block'; textarea.value = token; }
            if (typeof window.___grecaptcha_cfg !== 'undefined') {
              const clients = window.___grecaptcha_cfg.clients;
              for (const key in clients) {
                const client = clients[key];
                for (const k2 in client) {
                  const v = client[k2];
                  if (v && typeof v === 'object') {
                    for (const k3 in v) {
                      if (v[k3] && typeof v[k3].callback === 'function') {
                        v[k3].callback(token);
                        return;
                      }
                    }
                  }
                }
              }
            }
          }
        JS
        log("[Zoom] ✅ reCAPTCHA解決完了")
      end

    when 'hcaptcha'
      token = solve_with_2captcha(api_key, method: 'hcaptcha', sitekey: sitekey, pageurl: page_url)
      if token
        page.evaluate(<<~JS, arg: token)
          (token) => {
            const textarea = document.querySelector('[name="h-captcha-response"], [name="g-recaptcha-response"]');
            if (textarea) { textarea.value = token; }
            const iframe = document.querySelector('iframe[data-hcaptcha-widget-id]');
            const widgetId = iframe?.dataset?.hcaptchaWidgetId;
            if (widgetId && window.hcaptcha) {
              window.hcaptcha.execute(widgetId, { async: false });
            }
          }
        JS
        log("[Zoom] ✅ hCaptcha解決完了")
      end

    when 'turnstile'
      token = solve_with_2captcha(api_key, method: 'turnstile', sitekey: sitekey, pageurl: page_url)
      if token
        page.evaluate(<<~JS, arg: token)
          (token) => {
            const input = document.querySelector('[name="cf-turnstile-response"]');
            if (input) input.value = token;
            const cb = document.querySelector('.cf-turnstile')?.dataset?.callback;
            if (cb && typeof window[cb] === 'function') window[cb](token);
          }
        JS
        log("[Zoom] ✅ Turnstile解決完了")
      end
    end

    page.wait_for_timeout(1000)
    return true
  rescue => e
    log("[Zoom] ⚠️ CAPTCHA解決失敗: #{e.message}")
    return false
  end

  def solve_with_2captcha(api_key, params)
    require 'net/http'
    require 'json'

    # リクエスト送信
    uri = URI('https://2captcha.com/in.php')
    req_params = params.merge(key: api_key, json: 1)
    uri.query = URI.encode_www_form(req_params)
    res = Net::HTTP.get_response(uri)
    data = JSON.parse(res.body) rescue {}

    unless data['status'] == 1
      log("[Zoom] 2CAPTCHA送信失敗: #{data['request']}")
      return nil
    end

    captcha_id = data['request']
    log("[Zoom] 2CAPTCHA ID: #{captcha_id} — 解決待ち...")

    # ポーリング（最大120秒）
    result_uri = URI('https://2captcha.com/res.php')
    24.times do |i|
      sleep 5
      result_uri.query = URI.encode_www_form(key: api_key, action: 'get', id: captcha_id, json: 1)
      r = Net::HTTP.get_response(result_uri)
      rd = JSON.parse(r.body) rescue {}

      if rd['status'] == 1
        log("[Zoom] 2CAPTCHA解決成功（#{(i + 1) * 5}秒）")
        return rd['request']
      elsif rd['request'] != 'CAPCHA_NOT_READY'
        log("[Zoom] 2CAPTCHAエラー: #{rd['request']}")
        return nil
      end
      log("[Zoom] 2CAPTCHA待機中... #{(i + 1) * 5}秒") if (i + 1) % 4 == 0
    end

    log("[Zoom] 2CAPTCHAタイムアウト")
    nil
  end

  # ===== SCHEDULE =====
  def schedule_meeting(page, title:, start_date:, start_time:, duration_minutes:)
    log("[Zoom] スケジュール画面に直接アクセス中...")
    page.goto(SCHEDULE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
    page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
    page.wait_for_timeout(3000)

    log("[Zoom] ミーティングフォームを入力中...")

    # ===== トピック =====
    topic_input = page.locator('input[id*="topic"], input[name*="topic"], #topic').first
    topic_input.wait_for(state: 'visible', timeout: 10_000)
    topic_input.fill('')
    topic_input.fill(title)
    log("[Zoom] トピック: #{title}")

    # ===== 日時入力（ZoomのカスタムUI対応）=====
    fill_datetime_js(page, start_date, start_time, duration_minutes)

    # ===== 待機室を有効にする =====
    enable_waiting_room(page)

    # スクリーンショットで保存前の状態を確認
    screenshot_path = Rails.root.join('tmp', 'zoom_before_save.png').to_s
    page.screenshot(path: screenshot_path, fullPage: true) rescue nil

    # ===== 保存ボタン =====
    log("[Zoom] 保存ボタンを検索中...")

    # ページ最下部にスクロール
    page.evaluate('window.scrollTo(0, document.body.scrollHeight)')
    page.wait_for_timeout(1000)

    # 「保存」ボタンのみを対象（<button>タグ限定、ナビリンク<a>を除外）
    save_clicked = page.evaluate(<<~'JS')
      (() => {
        // button タグのみ（<a> ナビリンクを除外）
        const buttons = [...document.querySelectorAll('button')];
        for (const btn of buttons) {
          const text = (btn.textContent || '').trim();
          if (text === '保存' || text === 'Save') {
            btn.scrollIntoView({ block: 'center' });
            btn.click();
            return { found: true, text, tag: 'BUTTON', id: btn.id || '', cls: (btn.className || '').substring(0, 60) };
          }
        }
        // input[type=submit] もチェック
        const submits = [...document.querySelectorAll('input[type="submit"]')];
        for (const inp of submits) {
          const val = (inp.value || '').trim();
          if (val === '保存' || val === 'Save') {
            inp.scrollIntoView({ block: 'center' });
            inp.click();
            return { found: true, text: val, tag: 'INPUT', id: inp.id || '' };
          }
        }
        // フォールバック: フォーム末尾の青いボタン（primary button）
        const primaryBtns = document.querySelectorAll('button[class*="primary"], button[class*="submit"], .zm-btn--primary');
        if (primaryBtns.length > 0) {
          const btn = primaryBtns[primaryBtns.length - 1];
          btn.scrollIntoView({ block: 'center' });
          btn.click();
          return { found: true, text: (btn.textContent || '').trim(), tag: 'BUTTON-PRIMARY' };
        }
        // ボタン一覧をデバッグ出力
        const allBtns = buttons.map(b => ({ text: (b.textContent || '').trim().substring(0, 30), cls: (b.className || '').substring(0, 40) }));
        return { found: false, allButtons: allBtns };
      })()
    JS

    if save_clicked['found']
      log("[Zoom] 保存ボタンクリック: #{save_clicked['text']} (#{save_clicked['tag']})")
    else
      log("[Zoom] ボタン一覧: #{save_clicked['allButtons']&.to_json}")
      raise "保存ボタンが見つかりませんでした"
    end

    # 保存後のページ遷移を待つ
    page.wait_for_timeout(5000)
    page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
    page.wait_for_timeout(2000)

    # 保存後のスクリーンショット
    screenshot_path = Rails.root.join('tmp', 'zoom_after_save.png').to_s
    page.screenshot(path: screenshot_path, fullPage: true) rescue nil

    log("[Zoom] ✅ ミーティング保存完了 → #{page.url}")
  end

  # ===== 日時入力（Zoomカレンダーピッカー対応）=====
  def fill_datetime_js(page, start_date, start_time, duration_minutes)
    target_date = Date.parse(start_date.to_s) rescue Date.today + 7
    hour, minute = (start_time || '10:00').split(':').map(&:to_i)

    # --- 日付: カレンダーピッカーで選択 ---
    log("[Zoom] 開催日を #{target_date.strftime('%Y/%m/%d')} に設定中...")

    # 日付テキスト（2026/03/22 等）をクリックしてカレンダーを開く
    begin
      today_str = Date.today.strftime('%Y/%m/%d')
      page.locator("text=#{today_str}").first.click(timeout: 5_000)
      page.wait_for_timeout(1500)
    rescue
      # フォールバック: 日付表示部分を座標クリック
      page.evaluate("document.querySelector('.base-options-1, [class*=\"date\"]')?.scrollIntoView({ block: 'center' })")
      page.wait_for_timeout(500)
      begin
        # 日付表示のテキストを探してクリック
        page.evaluate(<<~'JS')
          (() => {
            const all = [...document.querySelectorAll('*')];
            for (const el of all) {
              const text = (el.textContent || '').trim();
              if (/^\d{4}\/\d{2}\/\d{2}$/.test(text)) {
                el.click();
                return true;
              }
            }
            return false;
          })()
        JS
        page.wait_for_timeout(1500)
      rescue
        log("[Zoom] ⚠️ カレンダーを開けませんでした")
      end
    end

    # カレンダーで月をナビゲートして日付を選択
    navigate_calendar(page, target_date)

    # --- 時刻: input[aria-label="Select start time"] + AM/PM セレクト ---
    time_12h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
    am_pm = hour >= 12 ? 'PM' : 'AM'
    time_str = "#{time_12h}:#{format('%02d', minute)}"

    log("[Zoom] 開始時刻を #{time_str} #{am_pm} に設定中...")

    # 時刻input: triple-click で全選択 → タイプで上書き
    begin
      time_input = page.locator('input[aria-label="Select start time"]').first
      time_input.click(clickCount: 3, timeout: 5_000)
      page.wait_for_timeout(300)
      page.keyboard.press('Backspace')
      page.keyboard.type(time_str)
      page.keyboard.press('Tab')
      page.wait_for_timeout(500)
      log("[Zoom] 時刻入力: #{time_str}")
    rescue => e
      log("[Zoom] ⚠️ 時刻入力失敗: #{e.message}")
    end

    # AM/PM: span[aria-label="Select start time unit"] をクリックしてドロップダウン表示
    begin
      ampm_btn = page.locator('span[aria-label="Select start time unit"], .zoom-select-input__span').first
      current_ampm = ampm_btn.text_content.strip rescue ''
      log("[Zoom] 現在のAM/PM: #{current_ampm}")

      if current_ampm != am_pm
        ampm_btn.click(timeout: 3_000)
        page.wait_for_timeout(800)
        # ドロップダウンからAM/PMを選択
        page.locator(".zoom-select-option__content:has-text('#{am_pm}')").first.click(timeout: 3_000)
        page.wait_for_timeout(500)
        log("[Zoom] AM/PM: #{am_pm} に切り替え完了")
      else
        log("[Zoom] AM/PM: #{am_pm}（変更不要）")
      end
    rescue => e
      log("[Zoom] ⚠️ AM/PM切り替え失敗: #{e.message}")
      # JSフォールバック
      page.evaluate(<<~JS, arg: am_pm)
        (ampm) => {
          const opts = document.querySelectorAll('.zoom-select-option__content');
          for (const opt of opts) {
            if (opt.textContent.trim() === ampm) { opt.click(); return true; }
          }
          return false;
        }
      JS
    end

    log("[Zoom] 所要時間: #{duration_minutes / 60}時間#{duration_minutes % 60 > 0 ? "#{duration_minutes % 60}分" : ''}")
  end

  # カレンダーピッカーで目標日付にナビゲートして選択
  def navigate_calendar(page, target_date)
    today = Date.today
    target_month_diff = (target_date.year * 12 + target_date.month) - (today.year * 12 + today.month)

    # 「次の月」ボタンで目標月まで移動
    if target_month_diff > 0
      target_month_diff.times do
        begin
          page.locator('button[aria-label="次の月"]').click(timeout: 2_000)
          page.wait_for_timeout(500)
        rescue
          break
        end
      end
      log("[Zoom] カレンダー: #{target_month_diff}ヶ月先に移動")
    elsif target_month_diff < 0
      target_month_diff.abs.times do
        begin
          page.locator('button[aria-label="前の月"]').click(timeout: 2_000)
          page.wait_for_timeout(500)
        rescue
          break
        end
      end
    end

    page.wait_for_timeout(500)

    # 目標日のセルをクリック
    day = target_date.day.to_s
    begin
      # available クラスのセルから正しい日を選ぶ（next-month, prev-month を避ける）
      clicked = page.evaluate(<<~JS, arg: { day: day })
        (args) => {
          const cells = document.querySelectorAll('td.available:not(.next-month):not(.prev-month)');
          for (const cell of cells) {
            if (cell.textContent.trim() === args.day) {
              cell.click();
              return { found: true, text: cell.textContent.trim(), cls: cell.className };
            }
          }
          // フォールバック: テキスト一致
          const allCells = document.querySelectorAll('td');
          for (const cell of allCells) {
            if (cell.textContent.trim() === args.day && !cell.classList.contains('disabled')) {
              cell.click();
              return { found: true, text: cell.textContent.trim(), cls: cell.className, fallback: true };
            }
          }
          return { found: false };
        }
      JS

      if clicked['found']
        log("[Zoom] 開催日: #{target_date.strftime('%Y/%m/%d')} 選択完了")
      else
        log("[Zoom] ⚠️ カレンダーで #{day} 日が見つかりませんでした")
      end
    rescue => e
      log("[Zoom] ⚠️ 日付セル選択失敗: #{e.message}")
    end

    page.wait_for_timeout(1000)
  end

  # ===== 待機室有効化 =====
  def enable_waiting_room(page)
    log("[Zoom] 待機室を有効にしています...")

    enabled = page.evaluate(<<~'JS')
      (() => {
        // "待機室" or "Waiting Room" のラベルに関連するチェックボックスを探す
        const labels = [...document.querySelectorAll('label, span, div')];
        for (const label of labels) {
          const text = (label.textContent || '').trim();
          if (text.includes('待機室') || text.includes('Waiting Room')) {
            // ラベルに紐づくcheckboxを探す
            let checkbox = label.querySelector('input[type="checkbox"]');
            if (!checkbox && label.htmlFor) {
              checkbox = document.getElementById(label.htmlFor);
            }
            if (!checkbox) {
              // 親要素や兄弟要素から探す
              const parent = label.closest('div, label, section');
              if (parent) checkbox = parent.querySelector('input[type="checkbox"]');
            }
            if (checkbox && !checkbox.checked) {
              checkbox.click();
              return { found: true, checked: true, method: 'checkbox' };
            } else if (checkbox && checkbox.checked) {
              return { found: true, checked: true, method: 'already_checked' };
            }

            // チェックボックスがない場合、ラベル自体をクリック
            label.click();
            return { found: true, checked: true, method: 'label_click' };
          }
        }
        return { found: false };
      })()
    JS

    if enabled['found']
      log("[Zoom] ✅ 待機室: #{enabled['method'] == 'already_checked' ? '既に有効' : '有効にしました'}")
    else
      log("[Zoom] ⚠️ 待機室のチェックボックスが見つかりませんでした")
    end
  end

  # ===== ミーティング情報取得 =====
  def extract_meeting_info(page)
    log("[Zoom] ミーティング情報を取得中...")
    page.wait_for_timeout(2000)

    result = page.evaluate(<<~'JS')
      (() => {
        const body = document.body.innerText || '';

        // Invite link
        let zoomUrl = '';
        const linkEl = document.querySelector('a[href*="zoom.us/j/"]');
        if (linkEl) {
          zoomUrl = linkEl.href;
        } else {
          const urlMatch = body.match(/(https:\/\/[a-z0-9]+\.zoom\.us\/j\/\d+[^\s<"]*)/i);
          if (urlMatch) zoomUrl = urlMatch[1];
        }

        // Meeting ID
        let meetingId = '';
        const idMatch = body.match(/(?:ミーティング\s*ID|Meeting\s*ID)[:\s]*([0-9\s]{9,})/i);
        if (idMatch) meetingId = idMatch[1].trim();

        // Passcode（数字のみを対象）
        let passcode = '';
        const pcMatch = body.match(/(?:パスコード|Passcode|パスワード|Password)[:\s]*(\d{4,10})/i);
        if (pcMatch) passcode = pcMatch[1].trim();

        return { zoomUrl, meetingId, passcode, pageUrl: location.href };
      })()
    JS

    zoom_url   = result['zoomUrl'].to_s.strip
    meeting_id = result['meetingId'].to_s.strip
    passcode   = result['passcode'].to_s.strip

    # パスコードが数字でない場合（マスクや不正テキスト）、「表示」ボタンで実パスコードを取得
    passcode = '' unless passcode.match?(/\A\d{4,10}\z/)
    if passcode.blank?
      log("[Zoom] パスコードがマスクされています。「表示」ボタンで実パスコードを取得中...")
      # パスコード付近のHTMLをデバッグ出力
      pc_debug = page.evaluate(<<~'DEBUG_JS')
        (() => {
          const body = document.body.innerText || '';
          const match = body.match(/.{0,30}パスコード.{0,50}/i) || body.match(/.{0,30}Passcode.{0,50}/i);
          return match ? match[0] : 'NOT_FOUND';
        })()
      DEBUG_JS
      log("[Zoom] パスコード周辺テキスト: #{pc_debug}")

      revealed = page.evaluate(<<~'REVEAL_JS')
        (() => {
          // パスコード行にある「表示」「Show」リンクを探してクリック
          const all = [...document.querySelectorAll('a, button, span')];
          for (const el of all) {
            const text = (el.textContent || '').trim();
            if (text === '表示' || text === 'Show' || text === 'show') {
              el.click();
              return { clicked: true, text };
            }
          }
          return { clicked: false };
        })()
      REVEAL_JS

      log("[Zoom] 表示ボタン: #{revealed.to_json}")

      if revealed['clicked']
        page.wait_for_timeout(1500)

        # クリック後のスクリーンショット
        page.screenshot(path: Rails.root.join('tmp', 'zoom_passcode_revealed.png').to_s) rescue nil

        # 表示されたパスコード（数字）を再取得
        revealed_passcode = page.evaluate(<<~'GET_PC_JS')
          (() => {
            const body = document.body.innerText || '';
            // パスコード: の後の数字を取得（マスクでない）
            const match = body.match(/(?:パスコード|Passcode)[:\s]*(\d{4,10})/i);
            if (match) return match[1].trim();
            // 「非表示」が出ていれば表示成功 → 近くの数字を探す
            const all = [...document.querySelectorAll('span, div, td, dd')];
            for (const el of all) {
              const text = (el.textContent || '').trim();
              if (/^\d{4,10}$/.test(text)) {
                const parent = el.closest('div, tr, section');
                if (parent && (parent.textContent.includes('パスコード') || parent.textContent.includes('Passcode'))) {
                  return text;
                }
              }
            }
            return '';
          })()
        GET_PC_JS
        if revealed_passcode.present?
          passcode = revealed_passcode
          log("[Zoom] ✅ パスコード取得成功: #{passcode}")
        else
          log("[Zoom] ⚠️ 表示ボタンクリック後もパスコードを取得できませんでした")
        end
      end
    end

    if zoom_url.blank? || !passcode.match?(/\A\d{4,10}\z/)
      log("[Zoom] 招待コピーから詳細情報を取得中...")
      begin
        # 「招待状をコピー」ボタンを幅広く検索
        copy_clicked = page.evaluate(<<~'JS2')
          (() => {
            const all = [...document.querySelectorAll('a, button, span, div')];
            for (const el of all) {
              const text = (el.textContent || '').trim();
              if (text.includes('招待状をコピー') || text.includes('Copy Invitation') ||
                  text.includes('招待リンクをコピー') || text.includes('Copy the invitation')) {
                el.click();
                return { found: true, text: text.substring(0, 30) };
              }
            }
            return { found: false };
          })()
        JS2
        log("[Zoom] 招待コピーボタン: #{copy_clicked.to_json}")

        if copy_clicked['found']
          page.wait_for_timeout(2000)

          # モーダルまたはテキストエリアから招待テキストを取得
          invite_text = page.evaluate(<<~'JS3')
            (() => {
              // モーダル内のテキスト
              const modal = document.querySelector('[role="dialog"], .zm-modal, [class*="modal"], [class*="Modal"]');
              if (modal) return modal.innerText || '';
              // テキストエリア
              const textarea = document.querySelector('textarea');
              if (textarea) return textarea.value || '';
              // クリップボードからは取れないので、ページ全体から
              return '';
            })()
          JS3

          if invite_text.present?
            log("[Zoom] 招待テキスト取得成功（#{invite_text.length}文字）")

            url_m = invite_text.match(/(https:\/\/[a-z0-9]+\.zoom\.us\/j\/\d+[^\s]*)/i)
            zoom_url = url_m[1] if url_m && zoom_url.blank?

            id_m = invite_text.match(/(?:ミーティング\s*ID|Meeting\s*ID)[:\s]*([0-9\s]{9,})/i)
            meeting_id = id_m[1].strip if id_m && meeting_id.blank?

            # 数字パスコードを優先取得
            pc_m = invite_text.match(/(?:パスコード|Passcode|パスワード|Password)[:\s]*(\d{4,10})/i)
            pc_m ||= invite_text.match(/(?:パスコード|Passcode|パスワード|Password)[:\s]*([^\s\n*]+)/i)
            passcode = pc_m[1].strip if pc_m && !pc_m[1].include?('*')
          end

          # モーダルを閉じる
          page.evaluate("document.querySelector('[role=\"dialog\"] button[aria-label*=\"閉\"], [role=\"dialog\"] button[aria-label*=\"close\"], .zm-modal-close')?.click()") rescue nil
          page.wait_for_timeout(500)
        end
      rescue => e
        log("[Zoom] ⚠️ 招待コピー取得失敗: #{e.message}")
      end
    end

    # 最終スクリーンショット
    screenshot_path = Rails.root.join('tmp', 'zoom_result.png').to_s
    page.screenshot(path: screenshot_path) rescue nil

    raise "Zoom招待リンクが取得できませんでした（ページURL: #{result['pageUrl']}）" if zoom_url.blank?

    log("[Zoom] ✅ 招待リンク: #{zoom_url}")
    log("[Zoom] ✅ ミーティングID: #{meeting_id}") if meeting_id.present?
    log("[Zoom] ✅ パスコード: #{passcode}") if passcode.present?

    { zoom_url: zoom_url, meeting_id: meeting_id, passcode: passcode }
  end
end
