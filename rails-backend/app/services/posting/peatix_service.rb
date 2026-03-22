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

      # ===== Step2: API でカテゴリ・説明文を設定 =====
      log("[Peatix] PATCH /v4/events/#{event_id} カテゴリ・説明文更新中...")
      zoom_info = ''
      zoom_info += "\n\n■ Zoom参加情報" if zoom_url.present?
      zoom_info += "\n参加URL: #{zoom_url}" if zoom_url.present?
      zoom_info += "\nミーティングID: #{zoom_id}" if zoom_id.present?
      zoom_info += "\nパスコード: #{zoom_passcode}" if zoom_passcode.present?

      patch_body = {
        details: { description: body_text + zoom_info },
        category: 'skills_qualifications',
        tags: ['生成AI', 'AIエージェント', 'リモートワーク', 'プログラミング', '転職'],
      }

      patch_result = page.evaluate(<<~JS, arg: { eventId: event_id, bearer: bearer, body: patch_body })
        async ({ eventId, bearer, body }) => {
          const res = await fetch(`https://peatix-api.com/v4/events/${eventId}`, {
            method: 'PATCH',
            headers: { 'content-type': 'application/json', 'authorization': `Bearer ${bearer}`,
                       'origin': 'https://peatix.com', 'referer': `https://peatix.com/event/${eventId}/edit`,
                       'x-requested-with': 'XMLHttpRequest' },
            body: JSON.stringify(body),
          });
          return { ok: res.ok, status: res.status, text: await res.text() };
        }
      JS
      log("[Peatix] API更新: #{patch_result['ok'] ? '✅ 成功' : "⚠️ #{patch_result['status']}"}")

      # ===== Step3: 編集ウィザードをPlaywrightで操作 =====
      edit_url = "https://peatix.com/event/#{event_id}/edit/basics"
      log("[Peatix] 編集画面に遷移: #{edit_url}")
      page.goto(edit_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
      page.wait_for_timeout(3000)

      # --- basics（配信URL・参加方法） ---
      fill_basics(page, zoom_url, zoom_id, zoom_passcode, body_text, content)

      # --- details（カバー画像）→ カテゴリはAPI設定済み ---
      fill_details(page, image_path)

      # --- tickets（無料チケット） ---
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

    # ===== details ページ（カテゴリ選択 + カバー画像） =====
    def fill_details(page, image_path)
      log("[Peatix] 📝 details: カテゴリ・画像を設定中...")
      # detailsページに遷移
      current = page.url
      if current.include?('/edit/') && !current.include?('/details')
        details_url = current.sub(%r{/edit/\w+}, '/edit/details')
        page.goto(details_url, waitUntil: 'domcontentloaded', timeout: 15_000)
        page.wait_for_load_state('networkidle', timeout: 10_000) rescue nil
        page.wait_for_timeout(2000)
      end

      # カテゴリ選択（mouse.click で FormKit セレクトを操作）
      select_category(page)

      # カバー画像アップロード
      upload_cover_image(page, image_path)

      # 「進む」をクリック
      click_next_button(page, 'details')
    end

    def select_category(page)
      begin
        btn = page.locator('button[name="category"]')
        box = btn.bounding_box(timeout: 5_000)
        if box
          page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
          page.wait_for_timeout(1500)

          # リストから「スキルアップ」を選択
          page.locator('[role="option"]:has-text("スキルアップ")').click(timeout: 5_000)
          page.wait_for_timeout(1500)
          log("[Peatix] カテゴリ: スキルアップ／資格 選択完了")

          # サブカテゴリ（タグ）入力
          select_subcategory_tags(page)
        else
          log("[Peatix] ⚠️ カテゴリボタンが画面外です")
        end
      rescue => e
        log("[Peatix] ⚠️ カテゴリ選択失敗: #{e.message}")
      end
    end

    def select_subcategory_tags(page)
      tags = ['生成AI', 'AIエージェント', 'リモートワーク', 'プログラミング', '転職']
      begin
        # タグ入力フィールドを探す（カテゴリ選択後に表示される）
        tag_input = page.locator('input[placeholder*="タグ"], input[name*="tag"], input[placeholder*="Tag"], input[type="text"][aria-autocomplete]').first
        tag_input.wait_for(state: 'visible', timeout: 5_000)

        tags.each do |tag|
          tag_input.fill(tag)
          page.wait_for_timeout(500)
          page.keyboard.press('Enter')
          page.wait_for_timeout(300)
        end
        log("[Peatix] サブカテゴリ: #{tags.join(', ')}")
      rescue => e
        # フォールバック: チェックボックス型の場合
        log("[Peatix] タグ入力欄なし、チェックボックス型を試行: #{e.message}")
        begin
          selected = []
          tags.each do |tag|
            opt = page.locator("text=#{tag}").first
            opt.click(timeout: 2_000) rescue next
            selected << tag
          end
          log("[Peatix] サブカテゴリ(checkbox): #{selected.join(', ')}") if selected.any?
        rescue
          log("[Peatix] ⚠️ サブカテゴリ選択失敗")
        end
      end
    end

    # ===== tickets ページ =====
    def fill_tickets(page)
      log("[Peatix] 🎫 tickets: 無料チケット設定中...")
      page.wait_for_timeout(2000)

      # 「無料チケット」カードをクリック
      begin
        free_ticket = page.evaluate(<<~'JS')
          (() => {
            const all = [...document.querySelectorAll('div, button, a, [role="button"]')];
            for (const el of all) {
              const text = (el.textContent || '').trim();
              if (text.includes('無料チケット') && !text.includes('有料')) {
                el.click();
                return { found: true, text: text.substring(0, 40) };
              }
            }
            return { found: false };
          })()
        JS
        log("[Peatix] 無料チケットカード: #{free_ticket.to_json}")

        if free_ticket['found']
          page.wait_for_timeout(2000)

          # チケット作成フォームのスクリーンショット
          page.screenshot(path: Rails.root.join('tmp', 'peatix_ticket_form.png').to_s, fullPage: true) rescue nil

          # チケット名を入力、枚数を50に設定
          page.evaluate(<<~'JS')
            (() => {
              const logs = [];
              const setVal = (el, v) => {
                if (!el) return;
                const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
                const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
                if (setter) setter.call(el, String(v));
                else el.value = String(v);
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
              };

              // チケット名（input[name="name"]のうち、チケット関連のもの）
              const allInputs = [...document.querySelectorAll('input[type="text"]')];
              for (const inp of allInputs) {
                const ph = inp.placeholder || '';
                if (ph.includes('チケット') || ph.includes('例）') || ph.includes('ticket')) {
                  setVal(inp, '無料チケット');
                  logs.push('name: 無料チケット');
                  break;
                }
              }

              // 枚数（input[type="number"] で purchaseLimit 以外）
              const numInputs = [...document.querySelectorAll('input[type="number"]')];
              for (const inp of numInputs) {
                const name = (inp.name || '').toLowerCase();
                const label = inp.closest('div, label')?.textContent || '';
                if (label.includes('枚数') || label.includes('定員') || label.includes('quantity') || name.includes('quantity') || name.includes('capacity')) {
                  setVal(inp, '50');
                  logs.push('quantity: 50');
                  break;
                }
              }

              return logs;
            })()
          JS
          log("[Peatix] チケット: 無料チケット 50枚 設定完了")
        end
      rescue => e
        log("[Peatix] ⚠️ チケット設定失敗: #{e.message}")
      end

      # 「進む」/「保存して進む」をクリック
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

    def upload_cover_image(page, image_path)
      return unless image_path.present? && File.exist?(image_path)
      begin
        # Peatixのカバー画像: id="event-file"
        file_input = page.locator('#event-file')
        file_input.set_input_files(image_path)
        page.wait_for_timeout(3000)
        log("[Peatix] 📸 カバー画像アップロード完了")
      rescue => e
        log("[Peatix] ⚠️ 画像アップロード失敗: #{e.message}")
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
