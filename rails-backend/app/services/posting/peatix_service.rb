module Posting
  class PeatixService < BaseService
    GROUP_ID = -> {
      url = ENV.fetch('PEATIX_CREATE_URL', 'https://peatix.com/group/16510066/event/create')
      m = url.match(/group\/(\d+)/)
      m ? m[1] : '16510066'
    }

    private

    def execute(page, content, ef)
      bearer = login_and_get_bearer(page)
      title  = extract_title(ef, content, 100)
      group_id = GROUP_ID.call

      # 本文整形
      lines = content.split("\n")
      first_line = lines.first.to_s.gsub(/\A[#\s「『【]+/, '').gsub(/[】』」\s]+\z/, '').strip
      body_text = (first_line.present? && title.include?(first_line)) ? lines.drop(1).join("\n").lstrip : content

      zoom_url      = ef['zoomUrl'].to_s
      zoom_id       = ef['zoomId'].to_s
      zoom_passcode = ef['zoomPasscode'].to_s
      zoom_passcode = '' unless zoom_passcode.match?(/\A\d{4,10}\z/)
      image_path    = ef['imagePath'].to_s

      start_utc = to_utc(ef['startDate'], ef['startTime'])
      end_utc   = to_utc(ef['endDate'].presence || ef['startDate'], ef['endTime'].presence || ef['startTime'])

      # ===== Step1: API でイベント作成 =====
      create_body = {
        name: title, groupId: group_id, locationType: 'online',
        schedulingType: 'single', countryId: 392,
        start: { utc: start_utc, timezone: 'Asia/Tokyo' },
        end:   { utc: end_utc,   timezone: 'Asia/Tokyo' },
      }
      log("[Peatix] POST /v4/events: \"#{title}\"")

      create_result = page.evaluate(<<~JS, arg: { body: create_body, bearer: bearer, groupId: group_id })
        async ({ body, bearer, groupId }) => {
          const res = await fetch('https://peatix-api.com/v4/events', {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'authorization': `Bearer ${bearer}`,
                       'origin': 'https://peatix.com', 'referer': `https://peatix.com/group/${groupId}/event/create`,
                       'x-requested-with': 'XMLHttpRequest' },
            body: JSON.stringify(body),
          });
          return { ok: res.ok, status: res.status, text: await res.text() };
        }
      JS

      raise "Peatix イベント作成失敗: #{create_result['status']} #{create_result['text']}" unless create_result['ok']

      created  = JSON.parse(create_result['text'])
      event_id = created['id'] || created['eventId']
      log("[Peatix] ✅ イベント作成 ID: #{event_id}")

      # ===== Step2: 編集ウィザードをPlaywrightで操作 =====
      edit_url = "https://peatix.com/event/#{event_id}/edit/basics"
      log("[Peatix] 編集画面に遷移: #{edit_url}")
      page.goto(edit_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
      page.wait_for_timeout(3000)

      # --- Step2a: basics（基本情報） ---
      fill_basics(page, zoom_url, zoom_id, zoom_passcode, body_text, content)

      # --- Step2b: details（詳細・カテゴリ・カバー画像） ---
      fill_details(page, image_path)

      # --- Step2c: tickets（チケット） ---
      fill_tickets(page)

      event_url = "https://peatix.com/event/#{event_id}"
      log("[Peatix] ✅ 全ステップ完了 → #{event_url}")
    end

    # ===== basics ページ =====
    def fill_basics(page, zoom_url, zoom_id, zoom_passcode, body_text, content)
      log("[Peatix] 📝 basics: 配信URL・参加方法を入力中...")

      # ページ下部にスクロールして隠れている要素を表示
      page.evaluate('window.scrollTo(0, document.body.scrollHeight)')
      page.wait_for_timeout(1000)

      participation_text = build_participation_text(zoom_url, zoom_id, zoom_passcode)

      # JS で直接操作（hidden 要素もname指定で確実に入力）
      fill_result = page.evaluate(<<~JS, arg: { zoomUrl: zoom_url, participation: participation_text })
        (args) => {
          const logs = [];
          const setVal = (el, v) => {
            if (!el) return false;
            const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
            if (setter) setter.call(el, v);
            else el.value = v;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            el.dispatchEvent(new Event('blur', { bubbles: true }));
            return true;
          };

          // 配信URL（name="url"）
          const urlInput = document.querySelector('input[name="url"]');
          if (urlInput && args.zoomUrl) {
            setVal(urlInput, args.zoomUrl);
            logs.push('配信URL: OK');
          } else {
            logs.push('配信URL: NOT_FOUND');
          }

          // 参加方法（name="attendeeInfo"）
          const attendeeTA = document.querySelector('textarea[name="attendeeInfo"]');
          if (attendeeTA) {
            setVal(attendeeTA, args.participation);
            logs.push('参加方法: OK (' + args.participation.length + '文字)');
          } else {
            // フォールバック: 最初のtextarea
            const ta = document.querySelector('textarea');
            if (ta) {
              setVal(ta, args.participation);
              logs.push('参加方法(fallback): OK');
            } else {
              logs.push('参加方法: NOT_FOUND');
            }
          }

          return logs;
        }
      JS

      Array(fill_result).each { |l| log("[Peatix] #{l}") }

      # スクリーンショット
      page.screenshot(path: Rails.root.join('tmp', 'peatix_basics_filled.png').to_s, fullPage: true) rescue nil

      # 「進む」/ 「保存して進む」をクリック
      click_next_button(page, 'basics')
    end

    # ===== details ページ（カテゴリ・カバー画像・イベント詳細） =====
    def fill_details(page, image_path)
      log("[Peatix] 📝 details: カテゴリ・画像・詳細を設定中...")
      page.wait_for_timeout(2000)

      # スクリーンショット
      page.screenshot(path: Rails.root.join('tmp', 'peatix_details.png').to_s, fullPage: true) rescue nil

      # カテゴリ選択: スキルアップ/資格
      select_category(page)

      # サブカテゴリ選択
      select_subcategories(page)

      # カバー画像アップロード
      upload_cover_image(page, image_path)

      # イベント詳細の改行修正
      fix_description_newlines(page)

      # 「保存して進む」をクリック
      click_next_button(page, 'details')
    end

    # ===== tickets ページ =====
    def fill_tickets(page)
      log("[Peatix] 🎫 tickets: 無料チケット設定中...")
      page.wait_for_timeout(2000)

      page.screenshot(path: Rails.root.join('tmp', 'peatix_tickets.png').to_s, fullPage: true) rescue nil

      # チケット追加ボタン探し
      add_ticket = page.evaluate(<<~'JS')
        (() => {
          const btns = [...document.querySelectorAll('button, a, [role="button"]')];
          for (const btn of btns) {
            const text = (btn.textContent || '').trim();
            if (text.includes('チケット') && (text.includes('追加') || text.includes('作成'))) {
              btn.click();
              return { found: true, text };
            }
          }
          // 既にチケットフォームがある場合
          const nameInput = document.querySelector('input[name*="ticket"], input[placeholder*="チケット"]');
          if (nameInput) return { found: true, text: 'form_exists' };
          return { found: false };
        })()
      JS
      log("[Peatix] チケット追加: #{add_ticket.to_json}")

      if add_ticket['found']
        page.wait_for_timeout(1500)

        # チケット名と枚数を入力
        page.evaluate(<<~'JS')
          (() => {
            const inputs = document.querySelectorAll('input[type="text"], input[type="number"]');
            for (const inp of inputs) {
              const ph = (inp.placeholder || inp.name || '').toLowerCase();
              const label = inp.closest('div, label, tr')?.textContent?.toLowerCase() || '';
              if (ph.includes('チケット') || ph.includes('ticket') || label.includes('チケット名') || label.includes('ticket name')) {
                inp.value = '無料チケット';
                inp.dispatchEvent(new Event('input', { bubbles: true }));
                inp.dispatchEvent(new Event('change', { bubbles: true }));
              }
              if (ph.includes('枚') || ph.includes('quantity') || ph.includes('num') || label.includes('枚数') || label.includes('数量')) {
                inp.value = '50';
                inp.dispatchEvent(new Event('input', { bubbles: true }));
                inp.dispatchEvent(new Event('change', { bubbles: true }));
              }
            }
            // 金額を0にする
            const priceInputs = document.querySelectorAll('input[type="number"]');
            for (const inp of priceInputs) {
              const label = inp.closest('div, label, tr')?.textContent?.toLowerCase() || '';
              if (label.includes('価格') || label.includes('金額') || label.includes('price')) {
                inp.value = '0';
                inp.dispatchEvent(new Event('input', { bubbles: true }));
                inp.dispatchEvent(new Event('change', { bubbles: true }));
              }
            }
          })()
        JS
        log("[Peatix] チケット: 無料チケット 50枚")
      end

      # 「保存して進む」をクリック
      click_next_button(page, 'tickets')
    end

    # ===== ヘルパーメソッド =====

    def build_participation_text(zoom_url, zoom_id, zoom_passcode)
      lines = []
      lines << "以下のZoom URLからご参加ください。"
      lines << "開始5分前になりましたらご入室いただけます。"
      lines << ""
      lines << "■ Zoom参加情報"
      lines << "参加URL: #{zoom_url}" if zoom_url.present?
      lines << "ミーティングID: #{zoom_id}" if zoom_id.present?
      lines << "パスコード: #{zoom_passcode}" if zoom_passcode.present?
      lines.join("\n")
    end

    def select_category(page)
      begin
        page.evaluate(<<~'JS')
          (() => {
            const selects = document.querySelectorAll('select');
            for (const sel of selects) {
              const label = sel.closest('div, label')?.textContent || '';
              if (label.includes('カテゴリ') || label.includes('Category')) {
                for (const opt of sel.options) {
                  if (opt.textContent.includes('スキルアップ') || opt.textContent.includes('資格')) {
                    sel.value = opt.value;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                    return 'selected: ' + opt.textContent.trim();
                  }
                }
              }
            }
            // ボタン/ラベルクリック型の場合
            const all = [...document.querySelectorAll('button, label, div, span, li, a')];
            for (const el of all) {
              const text = (el.textContent || '').trim();
              if (text === 'スキルアップ/資格' || text === 'スキルアップ・資格') {
                el.click();
                return 'clicked: ' + text;
              }
            }
            return 'not_found';
          })()
        JS
        log("[Peatix] カテゴリ: スキルアップ/資格")
      rescue => e
        log("[Peatix] ⚠️ カテゴリ選択失敗: #{e.message}")
      end
    end

    def select_subcategories(page)
      page.wait_for_timeout(1000)
      subcats = ['生成AI', 'AIエージェント', 'リモートワーク', 'プログラミング', '転職']
      begin
        selected = page.evaluate(<<~JS, arg: subcats)
          (keywords) => {
            const results = [];
            const all = [...document.querySelectorAll('button, label, div, span, li, a, input[type="checkbox"]')];
            for (const kw of keywords) {
              for (const el of all) {
                const text = (el.textContent || '').trim();
                if (text === kw || text.includes(kw)) {
                  if (el.tagName === 'INPUT' && el.type === 'checkbox') {
                    if (!el.checked) el.click();
                  } else {
                    el.click();
                  }
                  results.push(kw);
                  break;
                }
              }
            }
            return results;
          }
        JS
        log("[Peatix] サブカテゴリ: #{selected.join(', ')}")
      rescue => e
        log("[Peatix] ⚠️ サブカテゴリ選択失敗: #{e.message}")
      end
    end

    def upload_cover_image(page, image_path)
      return unless image_path.present? && File.exist?(image_path)
      begin
        file_inputs = page.locator('input[type="file"]')
        if file_inputs.count > 0
          file_inputs.first.set_input_files(image_path)
          page.wait_for_timeout(3000)
          log("[Peatix] 📸 カバー画像アップロード完了")
        else
          log("[Peatix] ⚠️ 画像アップロードフィールドなし")
        end
      rescue => e
        log("[Peatix] ⚠️ 画像アップロード失敗: #{e.message}")
      end
    end

    def fix_description_newlines(page)
      begin
        page.evaluate(<<~'JS')
          (() => {
            const textareas = document.querySelectorAll('textarea');
            for (const ta of textareas) {
              const label = ta.closest('div, section')?.textContent?.substring(0, 50) || '';
              if (label.includes('詳細') || label.includes('説明') || label.includes('description')) {
                // 改行が消えている場合に復元
                let val = ta.value;
                if (val && !val.includes('\n') && val.length > 100) {
                  // 句読点・記号の後に改行を入れる
                  val = val.replace(/([。！？\n])\s*/g, '$1\n');
                  val = val.replace(/(━+)/g, '\n$1\n');
                  val = val.replace(/(■\s)/g, '\n$1');
                  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
                  if (setter) setter.call(ta, val);
                  else ta.value = val;
                  ta.dispatchEvent(new Event('input', { bubbles: true }));
                  ta.dispatchEvent(new Event('change', { bubbles: true }));
                }
              }
            }
          })()
        JS
        log("[Peatix] 詳細文の改行修正完了")
      rescue => e
        log("[Peatix] ⚠️ 改行修正失敗: #{e.message}")
      end
    end

    def click_next_button(page, step_name)
      begin
        clicked = page.evaluate(<<~'JS')
          (() => {
            const btns = [...document.querySelectorAll('button, a, input[type="submit"]')];
            for (const btn of btns) {
              const text = (btn.textContent || btn.value || '').trim();
              if (text.includes('進む') || text.includes('保存して進む') || text === 'Next' || text === 'Save') {
                btn.scrollIntoView({ block: 'center' });
                btn.click();
                return { found: true, text };
              }
            }
            return { found: false };
          })()
        JS

        if clicked['found']
          log("[Peatix] #{step_name}: 「#{clicked['text']}」クリック")
          page.wait_for_timeout(3000)
          page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
          page.wait_for_timeout(2000)
        else
          log("[Peatix] ⚠️ #{step_name}: 進むボタンが見つかりません")
        end
      rescue => e
        log("[Peatix] ⚠️ #{step_name}: ボタンクリック失敗: #{e.message}")
      end
    end

    def login_and_get_bearer(page)
      log("[Peatix] ログイン中...")
      page.goto('https://peatix.com/signin', waitUntil: 'domcontentloaded', timeout: 30_000)

      unless page.url.include?('signin') || page.url.include?('login')
        log("[Peatix] ✅ ログイン済み → #{page.url}")
      else
        page.fill('input[name="username"]', ENV['PEATIX_EMAIL'].to_s)
        page.click('#next-button')
        page.wait_for_url('**/user/signin', timeout: 15_000) rescue nil
        page.wait_for_selector('input[type="password"]', timeout: 10_000) rescue nil
        page.fill('input[type="password"]', ENV['PEATIX_PASSWORD'].to_s)
        page.expect_navigation(timeout: 20_000) { page.click('#signin-button') } rescue nil

        after_url = page.url
        raise "Peatix ログイン失敗" if after_url.include?('signin') || after_url.include?('login')
        log("[Peatix] ✅ ログイン完了 → #{after_url}")
      end

      group_id   = GROUP_ID.call
      create_url = ENV.fetch('PEATIX_CREATE_URL', "https://peatix.com/group/#{group_id}/event/create")
      page.goto(create_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      token = page.evaluate("localStorage.getItem('peatix_frontend_access_token')")
      raise "Bearer トークンが取得できませんでした" if token.nil? || token.empty?
      log("[Peatix] Bearer取得: #{token[0, 8]}...")
      token
    end

    def to_utc(date_str, time_str)
      d = date_str.to_s.gsub('/', '-').presence || default_date_plus(30)
      t = pad_time(time_str || '10:00')
      Time.parse("#{d}T#{t}:00+09:00").utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end
  end
end
