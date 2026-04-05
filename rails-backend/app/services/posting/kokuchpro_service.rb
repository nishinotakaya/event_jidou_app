module Posting
  class KokuchproService < BaseService
    CREATE_URL = 'https://www.kokuchpro.com/regist/'

    FILL_FIELDS_JS = <<~'JS'
      (args) => {
        const { title, summary80, ymdDash, ymdEndDash, entry7, entry1,
                tStart, tEnd, cap, place, zoomUrl, tel, email } = args;
        const logs = [];
        const $ = window.jQuery || window.$ || null;

        const find = (...sels) => {
          for (const s of sels) {
            try { const el = document.querySelector(s); if (el) return el; } catch (_) {}
          }
          return null;
        };

        const setSelectOpt = (el, v) => {
          if (!el || el.tagName !== 'SELECT') return false;
          const ival = parseInt(v);
          for (const o of el.options) {
            if (o.value === String(v)) { el.value = o.value; el.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          }
          for (const o of el.options) {
            if (parseInt(o.value) === ival && !isNaN(ival)) { el.value = o.value; el.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          }
          return false;
        };

        const setDate = (el, ymd) => {
          if (!el) return 'NOT_FOUND';
          el.removeAttribute('disabled'); el.removeAttribute('readonly');
          const [yr, mo, dy] = ymd.split('-').map(Number);
          if ($ && $.fn && $.fn.datepicker && el.classList.contains('hasDatepicker')) {
            try {
              $(el).datepicker('setDate', new Date(yr, mo - 1, dy));
              el.dispatchEvent(new Event('input', { bubbles: true }));
              return 'jq:' + el.value;
            } catch (e) {}
          }
          el.value = ymd;
          el.dispatchEvent(new Event('input',  { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          el.dispatchEvent(new Event('blur',   { bubbles: true }));
          return 'direct:' + el.value;
        };

        const setTime = (baseName, timeStr) => {
          const [h, m] = timeStr.split(':');
          const el = find(`[name="${baseName}"]`);
          if (el) {
            if (el.tagName === 'SELECT') {
              setSelectOpt(el, timeStr) || setSelectOpt(el, `${parseInt(h)}:${m}`) || setSelectOpt(el, h);
              return 'select:' + el.value;
            }
            el.value = timeStr;
            el.dispatchEvent(new Event('input',  { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return 'input:' + el.value;
          }
          const hEl = find(`[name="${baseName}[hour]"]`);
          const mEl = find(`[name="${baseName}[min]"]`);
          if (hEl) setSelectOpt(hEl, h);
          if (mEl) setSelectOpt(mEl, m);
          return `sub:${hEl?.value}:${mEl?.value}`;
        };

        const setVal = (el, v) => {
          if (!el) return false;
          el.removeAttribute('disabled'); el.removeAttribute('readonly');
          const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
          if (setter) setter.call(el, String(v)); else el.value = String(v);
          el.dispatchEvent(new Event('input',  { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        };

        const nameEl = find('#EventName', '[name="data[Event][name]"]');
        setVal(nameEl, title);
        logs.push(`name: ${nameEl ? '"' + nameEl.value.slice(0, 30) + '"' : 'NOT_FOUND'}`);

        const descEl = find('#EventDescription', '[name="data[Event][description]"]');
        if (descEl) {
          const hasTiny = typeof tinymce !== 'undefined' && tinymce.get && tinymce.get(descEl.id);
          if (hasTiny) { hasTiny.setContent(summary80); hasTiny.save(); logs.push('description: TinyMCE設定'); }
          else { setVal(descEl, summary80); logs.push(`description: ${descEl.value.length}文字`); }
        } else { logs.push('description: NOT_FOUND'); }

        const genreEl = find('[name="data[Event][genre]"]', '#EventGenre');
        if (genreEl && genreEl.tagName === 'SELECT') {
          const opt = [...genreEl.options].find(o => o.value && o.value !== '' && o.value !== '0');
          if (opt) { genreEl.value = opt.value; genreEl.dispatchEvent(new Event('change', { bubbles: true })); }
        }

        logs.push(`start_date: ${setDate(find('#EventDateStartDateDate', '[name="data[EventDate][start_date_date]"]'), ymdDash)}`);
        logs.push(`end_date:   ${setDate(find('#EventDateEndDateDate',   '[name="data[EventDate][end_date_date]"]'),   ymdEndDash)}`);
        logs.push(`start_time: ${setTime('data[EventDate][start_date_time]', tStart)}`);
        logs.push(`end_time:   ${setTime('data[EventDate][end_date_time]',   tEnd)}`);
        logs.push(`entry_start: ${setDate(find('#EventDateEntryStartDateDate', '[name="data[EventDate][entry_start_date_date]"]'), entry7)}`);
        logs.push(`entry_end:   ${setDate(find('#EventDateEntryEndDateDate',   '[name="data[EventDate][entry_end_date_date]"]'),   entry1)}`);
        logs.push(`entry_start_time: ${setTime('data[EventDate][entry_start_date_time]', '00:00')}`);
        logs.push(`entry_end_time:   ${setTime('data[EventDate][entry_end_date_time]',   tStart)}`);

        setVal(find('#EventDateTotalCapacity', '[name="data[EventDate][total_capacity]"]'), cap);
        setVal(find('#EventPlace',             '[name="data[Event][place]"]'),              place);
        if (zoomUrl) setVal(find('#EventPlaceUrl', '[name="data[Event][place_url]"]'), zoomUrl);
        const countryEl = find('[name="data[Event][country]"]');
        if (countryEl) setSelectOpt(countryEl, 'JPN');
        setVal(find('#EventTel',   '[name="data[Event][tel]"]'),   tel);
        setVal(find('#EventEmail', '[name="data[Event][email]"]'), email);

        return logs;
      }
    JS

    private

    def execute(page, content, ef)
      title = extract_title(ef, content)

      log("[こくチーズ] /regist/ にアクセス中...")
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(1500)

      # Login if redirected
      if page.url.include?('login') || page.url.include?('signin')
        log("[こくチーズ] ログイン中...")
        page.fill('#LoginFormEmail', ENV['CONPASS__KOKUCIZE_MAIL'].to_s)
        page.fill('#LoginFormPassword', ENV['CONPASS_KOKUCIZE_PASSWORD'].to_s)
        page.expect_navigation(timeout: 30_000) { page.click('#UserLoginForm button[type="submit"]') } rescue nil
        page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
        raise "ログインに失敗しました" if page.url.include?('login') || page.url.include?('signin')
        log("[こくチーズ] ✅ ログイン完了 → #{page.url}")
      else
        log("[こくチーズ] ✅ ログイン済み")
      end

      # Step1: event type + fee
      has_step1 = page.locator('input[name="data[Event][event_type]"]').first.visible?(timeout: 2_000) rescue false
      if has_step1
        log("[こくチーズ] Step1: イベント種別選択")
        page.locator('input[name="data[Event][event_type]"][value="0"]').check rescue nil
        page.locator('input[name="data[Event][charge]"][value="0"]').check rescue nil
        page.evaluate(<<~JS)
          const f = [...document.querySelectorAll('form')].find(f => f.querySelector('input[name="data[step]"]'));
          if (f) f.submit();
        JS
        page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
        log("[こくチーズ] Step2へ → #{page.url}")
      end

      page.wait_for_timeout(2500)

      # Date/time setup
      start_date = ef['startDate'].present? ? normalize_date(ef['startDate']) : default_date_plus(30)
      end_date   = ef['endDate'].present?   ? normalize_date(ef['endDate'])   : start_date
      t_start = pad_time(ef['startTime'] || '10:00')
      t_end   = pad_time(ef['endTime']   || '12:00')
      place   = ef['place'].presence || 'オンライン'
      cap     = ef['capacity'].presence || '50'
      tel     = parse_tel(ef['tel'])
      entry_start = Date.today.strftime('%Y-%m-%d')
      entry_end   = start_date
      summary80 = content.gsub("\n", ' ').gsub(/\s+/, ' ').strip[0, 80].presence || 'イベントのご案内です。'

      # TinyMCE content
      tiny_result = page.evaluate("(html) => { if (typeof tinymce === 'undefined' || !tinymce.editors || tinymce.editors.length === 0) return []; const results = []; tinymce.editors.forEach(ed => { const id = (ed.id || '').toLowerCase(); if (id.includes('body') || id.includes('page') || id.includes('html')) { ed.setContent(html.replace(/\\n/g, '<br>')); ed.save(); results.push({ id: ed.id, role: 'body' }); } else { results.push({ id: ed.id, role: 'other' }); } }); return results; }", arg: content) rescue []
      log("[こくチーズ] TinyMCEエディタ: #{tiny_result.to_json}") if tiny_result&.length.to_i > 0

      # Fill all fields
      fill_args = {
        title: title, summary80: summary80,
        ymdDash: start_date, ymdEndDash: end_date,
        entry7: entry_start, entry1: entry_end,
        tStart: t_start, tEnd: t_end,
        cap: cap, place: place,
        zoomUrl: ef['zoomUrl'].to_s,
        tel: tel, email: ENV['CONPASS__KOKUCIZE_MAIL'].to_s,
      }
      fill_result = page.evaluate(FILL_FIELDS_JS, arg: fill_args)
      Array(fill_result).each { |l| log("[こくチーズ] #{l}") }

      # Sub-genre
      page.wait_for_timeout(600)
      page.evaluate("const sel = document.querySelector('#EventGenreSub, [name=\"data[Event][genre_sub]\"]'); if (sel && sel.tagName === 'SELECT') { const opt = [...sel.options].find(o => o.value && o.value !== '' && o.value !== '0'); if (opt) { sel.value = opt.value; sel.dispatchEvent(new Event('change', { bubbles: true })); } }") rescue nil

      # Image upload
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        log("[こくチーズ] 📸 画像アップロード中...")
        begin
          file_inputs = page.locator('input[type="file"]')
          if file_inputs.count > 0
            file_inputs.first.set_input_files(ef['imagePath'])
            page.wait_for_timeout(2000)
            log("[こくチーズ] ✅ 画像アップロード完了")
          else
            log("[こくチーズ] ⚠️ 画像アップロードフィールドが見つかりません")
          end
        rescue => e
          log("[こくチーズ] ⚠️ 画像アップロード失敗: #{e.message}")
        end
      end

      # Daily limit check
      page_text = page.evaluate("document.documentElement.textContent || ''")
      if page_text.include?('登録数が制限') || page_text.include?('1日最大') || page_text.include?('明日以降にイベント')
        raise "日次制限エラー: こくちーずの1日3件制限に達しました"
      end

      # Find submit button
      reg_btn = page.evaluate(<<~JS)
        (() => {
          const submits = [...document.querySelectorAll('input[type="submit"]')];
          const reg = submits.find(b => { const v = b.value || ''; return !v.includes('選び直す') && !v.includes('戻る') && !v.includes('キャンセル') && !v.includes('検索'); });
          if (reg) return { tag: 'INPUT', value: reg.value, selector: `input[type="submit"][value="${reg.value}"]` };
          const btns = [...document.querySelectorAll('button[type="submit"]')];
          const regBtn = btns.find(b => { const form = b.closest('form'); return form && form.querySelector('[name="data[EventDate][start_date_date]"]'); });
          if (regBtn) return { tag: 'BUTTON', value: regBtn.textContent?.trim() || '', selector: null };
          return { tag: null };
        })()
      JS

      log("[こくチーズ] 登録ボタン: #{reg_btn.to_json}")
      raise "送信ボタンが見つかりません" unless reg_btn['tag']

      submit_btn = if reg_btn['selector']
        page.locator(reg_btn['selector']).first
      else
        event_form = page.locator('form').filter(has: page.locator('[name="data[EventDate][start_date_date]"]'))
        event_form.locator('button[type="submit"]').first
      end

      submit_btn.scroll_into_view_if_needed rescue nil
      log("[こくチーズ] 送信: \"#{reg_btn['value']}\"")
      page.expect_navigation(timeout: 30_000) { submit_btn.click } rescue nil
      page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil

      if page.url.include?('/regist/')
        errors = page.evaluate("[...document.querySelectorAll('.error-message, [class*=\"error\"], .alert, .alert-error')].map(el => el.textContent.trim()).filter(Boolean).join(' / ')") rescue ''
        raise "登録失敗: #{errors.presence || '不明'}"
      end

      admin_url = page.url  # 投稿完了後の管理画面URL
      log("[こくチーズ] ✅ 投稿完了 → #{admin_url}")

      # チケット追加
      add_ticket(page, start_date, t_start, cap)

      # メール設定（申込完了メール・キャンセルメール）
      setup_mail(page, title, start_date, t_start, t_end, place, ef)

      # 公開処理
      publish_sites = ef['publishSites'] || {}
      if publish_sites['こくチーズ']
        publish_event(page, admin_url)
      end
    end

    # ===== 公開処理 =====
    def publish_event(page, admin_url = nil)
      log("[こくチーズ] 🌐 公開処理中...")
      begin
        # 管理画面に遷移
        if admin_url.present?
          log("[こくチーズ] 管理画面: #{admin_url}")
          page.goto(admin_url, waitUntil: 'domcontentloaded', timeout: 15_000)
        end
        page.wait_for_load_state('networkidle', timeout: 10_000) rescue nil
        page.wait_for_timeout(2000)

        # アラートダイアログ（「この開催日のイベントを公開してもよろしいですか？」）を自動承認
        page.on('dialog', ->(dialog) {
          log("[こくチーズ] 🌐 アラート: #{dialog.message}")
          dialog.accept
        })

        # 「公開する」ボタンをクリック
        clicked = page.evaluate(<<~'JS')
          (() => {
            const btns = [...document.querySelectorAll('a, button, input[type="submit"]')];
            for (const btn of btns) {
              const text = (btn.textContent || btn.value || '').trim();
              if (text.includes('公開する') || text === '公開') {
                btn.scrollIntoView({ block: 'center' });
                btn.click();
                return { found: true, text };
              }
            }
            return { found: false };
          })()
        JS

        if clicked['found']
          page.wait_for_timeout(5000)
          page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
          log("[こくチーズ] 🌐 ✅ 公開完了")
        else
          log("[こくチーズ] ⚠️ 「公開する」ボタンが見つかりません")
        end
      rescue => e
        log("[こくチーズ] ⚠️ 公開処理失敗: #{e.message}")
      end
    end

    # ===== チケット追加 =====
    def add_ticket(page, start_date, start_time, capacity)
      log("[こくチーズ] 🎫 チケット追加中...")

      # 管理画面のURLからチケット追加リンクを探す
      begin
        # 投稿完了後のページからチケット追加リンクを探す
        ticket_link = page.locator(
          'a:has-text("チケット"), ' \
          'a:has-text("ticket"), ' \
          'a[href*="ticket"]'
        ).first
        ticket_link.wait_for(state: 'visible', timeout: 5_000)
        ticket_link.click
        page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
        page.wait_for_timeout(2000)
      rescue
        # フォールバック: 現在のURLからチケットページを推測
        current_url = page.url
        if current_url.include?('/admin/')
          ticket_url = current_url.sub(/\/$/, '') + '/ticket/'
          log("[こくチーズ] チケットページに直接アクセス: #{ticket_url}")
          page.goto(ticket_url, waitUntil: 'domcontentloaded', timeout: 15_000)
          page.wait_for_load_state('networkidle', timeout: 10_000) rescue nil
          page.wait_for_timeout(2000)
        else
          log("[こくチーズ] ⚠️ チケットページが見つかりません")
          return
        end
      end

      # 「イベントチケットの追加」ボタンを探してクリック
      begin
        add_btn = page.locator(
          'a:has-text("イベントチケットの追加"), ' \
          'a:has-text("チケットの追加"), ' \
          'a:has-text("チケットを追加"), ' \
          'button:has-text("チケットの追加"), ' \
          'a[href*="ticket/add"], ' \
          'a[href*="ticket/regist"]'
        ).first
        add_btn.wait_for(state: 'visible', timeout: 5_000)
        add_btn.click
        page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
        page.wait_for_timeout(2000)
      rescue => e
        log("[こくチーズ] ⚠️ チケット追加ボタンが見つかりません: #{e.message}")
        return
      end

      # チケットフォーム入力
      deadline_date = start_date
      deadline_time = start_time

      ticket_args = {
        name: 'オンラインチケット',
        capacity: capacity.to_s,
        deadlineDate: deadline_date,
        deadlineTime: deadline_time,
      }
      ticket_result = page.evaluate(<<~JS, arg: ticket_args)
        (args) => {
          const logs = [];
          const setVal = (el, v) => {
            if (!el) return false;
            el.removeAttribute('disabled'); el.removeAttribute('readonly');
            const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
            if (setter) setter.call(el, String(v)); else el.value = String(v);
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
          };

          // チケット名
          const nameEl = document.querySelector('[name*="ticket_name"], [name*="name"], input[id*="TicketName"], input[id*="ticketName"]');
          if (nameEl) { setVal(nameEl, args.name); logs.push('name: ' + args.name); }
          else {
            // 全inputから「チケット名」に近いものを探す
            const inputs = [...document.querySelectorAll('input[type="text"]')];
            if (inputs.length > 0) { setVal(inputs[0], args.name); logs.push('name(fallback): ' + args.name); }
          }

          // 販売枚数
          const capEl = document.querySelector('[name*="capacity"], [name*="num"], [name*="quantity"], input[type="number"]');
          if (capEl) { setVal(capEl, args.capacity); logs.push('capacity: ' + args.capacity); }

          // 締切日
          const dateInputs = document.querySelectorAll('input');
          for (const inp of dateInputs) {
            const n = (inp.name || '').toLowerCase();
            const id = (inp.id || '').toLowerCase();
            if (n.includes('deadline') || n.includes('limit') || n.includes('close') || id.includes('deadline') || id.includes('limit')) {
              if (inp.type === 'date' || /\\d{4}/.test(inp.value)) {
                setVal(inp, args.deadlineDate);
                logs.push('deadline_date: ' + args.deadlineDate);
              }
              if (inp.type === 'time' || /\\d{1,2}:\\d{2}/.test(inp.value)) {
                setVal(inp, args.deadlineTime);
                logs.push('deadline_time: ' + args.deadlineTime);
              }
            }
          }

          // 日付セレクトの場合
          const setDate = (el, ymd) => {
            if (!el) return;
            if (typeof $ !== 'undefined' && $.fn && $.fn.datepicker && el.classList.contains('hasDatepicker')) {
              const [yr, mo, dy] = ymd.split('-').map(Number);
              $(el).datepicker('setDate', new Date(yr, mo - 1, dy));
            } else {
              setVal(el, ymd);
            }
          };

          // 締切日を日付系inputから探す（より広い検索）
          if (!logs.some(l => l.startsWith('deadline'))) {
            const allInputs = [...document.querySelectorAll('input')];
            const dateInput = allInputs.find(i => i.type === 'date' || i.classList.contains('hasDatepicker'));
            if (dateInput) {
              setDate(dateInput, args.deadlineDate);
              logs.push('deadline_date(broad): ' + args.deadlineDate);
            }

            // 時刻select
            const timeSelects = document.querySelectorAll('select');
            for (const sel of timeSelects) {
              const n = (sel.name || sel.id || '').toLowerCase();
              if (n.includes('hour') || n.includes('time')) {
                const [h, m] = args.deadlineTime.split(':');
                for (const o of sel.options) {
                  if (o.value === h || parseInt(o.value) === parseInt(h)) {
                    sel.value = o.value;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                    logs.push('deadline_hour: ' + o.value);
                    break;
                  }
                }
              }
              if (n.includes('min')) {
                const [, m] = args.deadlineTime.split(':');
                for (const o of sel.options) {
                  if (o.value === m || parseInt(o.value) === parseInt(m)) {
                    sel.value = o.value;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                    logs.push('deadline_min: ' + o.value);
                    break;
                  }
                }
              }
            }
          }

          return logs;
        }
      JS

      Array(ticket_result).each { |l| log("[こくチーズ] 🎫 #{l}") }

      # スクリーンショットで確認
      screenshot_path = Rails.root.join('tmp', 'kokuchpro_ticket_form.png').to_s
      page.screenshot(path: screenshot_path) rescue nil

      # 「追加する」ボタンをクリック
      begin
        submit_clicked = page.evaluate(<<~'JS2')
          (() => {
            const btns = [...document.querySelectorAll('button, input[type="submit"]')];
            for (const btn of btns) {
              const text = (btn.textContent || btn.value || '').trim();
              if (text.includes('追加') || text === '登録' || text === '保存') {
                btn.scrollIntoView({ block: 'center' });
                btn.click();
                return { found: true, text };
              }
            }
            return { found: false };
          })()
        JS2

        if submit_clicked['found']
          log("[こくチーズ] 🎫 送信: #{submit_clicked['text']}")
          page.wait_for_timeout(3000)
          page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
          log("[こくチーズ] 🎫 ✅ チケット「オンラインチケット」追加完了")
        else
          log("[こくチーズ] ⚠️ チケット追加ボタンが見つかりません")
        end
      rescue => e
        log("[こくチーズ] ⚠️ チケット追加失敗: #{e.message}")
      end
    end

    # ===== メール設定 =====
    def setup_mail(page, title, start_date, start_time, end_time, place, ef)
      log("[こくチーズ] 📧 メール設定中...")

      # メール設定ページに遷移
      current_url = page.url
      mail_url = current_url.gsub(%r{/admin/}, '/edit/mail/').gsub(%r{/ticket/.*}, '/').sub(%r{/$}, '/')
      # URL パターン: /edit/mail/e-xxx/d-xxx/
      unless mail_url.include?('/edit/mail/')
        # 管理画面URLからメールURLを構築
        if current_url =~ %r{/(e-[^/]+/d-[^/]+)}
          event_path = $1
          mail_url = "https://www.kokuchpro.com/edit/mail/#{event_path}/"
        else
          log("[こくチーズ] ⚠️ メール設定URLを構築できません: #{current_url}")
          return
        end
      end

      log("[こくチーズ] メール設定ページ: #{mail_url}")
      page.goto(mail_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
      page.wait_for_timeout(2000)

      # ページ構造をデバッグ出力
      page.screenshot(path: Rails.root.join('tmp', 'kokuchpro_mail_page.png').to_s) rescue nil

      # 日付を日本語フォーマットに
      date_jp = begin
        d = Date.parse(start_date)
        wdays = %w[日 月 火 水 木 金 土]
        "#{d.year}年#{d.month}月#{d.day}日(#{wdays[d.wday]})"
      rescue
        start_date
      end

      zoom_url = ef['zoomUrl'].to_s
      zoom_id = ef['zoomId'].to_s
      zoom_passcode = ef['zoomPasscode'].to_s

      # パスコードが数字でない場合（マスクやゴミ）、DBから最新の数字パスコードを取得
      unless zoom_passcode.match?(/\A\d{4,10}\z/)
        if zoom_url.present?
          db_setting = ZoomSetting.where('zoom_url LIKE ?', "%#{zoom_url.split('/j/').last&.split('?')&.first}%")
                                  .where("passcode REGEXP ?", '^[0-9]{4,10}$')
                                  .order(updated_at: :desc).first rescue nil
          # SQLiteはREGEXPサポートしないのでRubyでフィルタ
          unless db_setting
            db_setting = ZoomSetting.order(updated_at: :desc).select { |s| s.passcode.to_s.match?(/\A\d{4,10}\z/) }.first rescue nil
          end
          zoom_passcode = db_setting.passcode if db_setting
        end
        zoom_passcode = '' unless zoom_passcode.match?(/\A\d{4,10}\z/)
      end

      # 申込完了メール本文
      apply_body = <<~MAIL
この度はお申込みいただきありがとうございます。

■ イベント詳細
━━━━━━━━━━━━━━━━
イベント名: #{title}
開催日時: #{date_jp} #{start_time}〜#{end_time}
会場: #{place}
━━━━━━━━━━━━━━━━
      MAIL

      if zoom_url.present?
        zoom_lines = ["参加URL: #{zoom_url}"]
        zoom_lines << "ミーティングID: #{zoom_id}" if zoom_id.present?
        zoom_lines << "パスコード: #{zoom_passcode}" if zoom_passcode.present?

        apply_body += "\n■ Zoom参加情報\n━━━━━━━━━━━━━━━━\n"
        apply_body += zoom_lines.join("\n") + "\n"
        apply_body += "━━━━━━━━━━━━━━━━\n\n"
        apply_body += "※ 開始5分前になりましたらURLよりご入室ください。\n"
      end

      apply_body += <<~FOOTER

ご不明な点がございましたら、お気軽にお問い合わせください。
当日お会いできることを楽しみにしております。
      FOOTER

      # キャンセルメール本文
      cancel_body = <<~CANCEL
キャンセルを承りました。

■ キャンセル対象イベント
━━━━━━━━━━━━━━━━
イベント名: #{title}
開催日時: #{date_jp} #{start_time}〜#{end_time}
━━━━━━━━━━━━━━━━

またの機会にぜひご参加ください。
ありがとうございました。
      CANCEL

      # フォームにテキストを入力
      mail_args = { applyBody: apply_body.strip, cancelBody: cancel_body.strip }
      mail_result = page.evaluate(<<~JS, arg: mail_args)
        (args) => {
          const logs = [];
          const textareas = [...document.querySelectorAll('textarea')];
          const labels = [...document.querySelectorAll('label, h3, h4, th, dt, .label, legend')];

          const setTextarea = (textarea, value) => {
            if (!textarea) return false;
            const nativeSetter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
            if (nativeSetter) nativeSetter.call(textarea, value);
            else textarea.value = value;
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
            textarea.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
          };

          // ラベルテキストからテキストエリアを特定する
          const findTextareaByLabel = (keywords) => {
            for (const label of labels) {
              const text = (label.textContent || '').trim();
              if (keywords.some(kw => text.includes(kw))) {
                // label の for 属性
                if (label.htmlFor) {
                  const ta = document.getElementById(label.htmlFor);
                  if (ta && ta.tagName === 'TEXTAREA') return ta;
                }
                // 近傍のtextarea
                const parent = label.closest('tr, div, section, fieldset, .form-group');
                if (parent) {
                  const ta = parent.querySelector('textarea');
                  if (ta) return ta;
                }
              }
            }
            return null;
          };

          // 申込完了メール
          let applyTa = findTextareaByLabel(['申込完了', '申し込み完了', '参加確定', '受付完了']);
          if (!applyTa && textareas.length >= 1) {
            applyTa = textareas[0]; // 最初のtextareaをフォールバック
          }
          if (applyTa) {
            setTextarea(applyTa, args.applyBody);
            logs.push('apply_mail: set (' + args.applyBody.length + ' chars)');
          } else {
            logs.push('apply_mail: NOT_FOUND');
          }

          // キャンセルメール
          let cancelTa = findTextareaByLabel(['キャンセル', 'cancel', '取消']);
          if (!cancelTa && textareas.length >= 2) {
            cancelTa = textareas[1]; // 2番目のtextarea
          }
          if (cancelTa) {
            setTextarea(cancelTa, args.cancelBody);
            logs.push('cancel_mail: set (' + args.cancelBody.length + ' chars)');
          } else {
            logs.push('cancel_mail: NOT_FOUND');
          }

          // 全textarea情報をデバッグ
          logs.push('textareas: ' + textareas.map((t, i) => i + ':' + (t.name || t.id || '(no-name)') + '[' + t.value.substring(0, 20) + '...]').join(', '));

          return logs;
        }
      JS

      Array(mail_result).each { |l| log("[こくチーズ] 📧 #{l}") }

      # スクリーンショット（入力後）
      page.screenshot(path: Rails.root.join('tmp', 'kokuchpro_mail_filled.png').to_s, fullPage: true) rescue nil

      # 「更新する」ボタンをクリック
      begin
        update_clicked = page.evaluate(<<~'JS2')
          (() => {
            const btns = [...document.querySelectorAll('button, input[type="submit"]')];
            for (const btn of btns) {
              const text = (btn.textContent || btn.value || '').trim();
              if (text.includes('更新') || text === '保存' || text === 'Save') {
                btn.scrollIntoView({ block: 'center' });
                btn.click();
                return { found: true, text };
              }
            }
            return { found: false };
          })()
        JS2

        if update_clicked['found']
          log("[こくチーズ] 📧 更新ボタンクリック: #{update_clicked['text']}")
          page.wait_for_timeout(3000)
          page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
          log("[こくチーズ] 📧 ✅ メール設定完了")
        else
          log("[こくチーズ] ⚠️ 更新ボタンが見つかりません")
        end
      rescue => e
        log("[こくチーズ] ⚠️ メール設定更新失敗: #{e.message}")
      end
    end

    def parse_tel(raw)
      return '03-1234-5678' if raw.blank?
      raw =~ /^\d{2,4}-\d{4}-\d{4}$/ ? raw : '03-1234-5678'
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      kokuchpro_ensure_login(page)
      admin_url = event_url.include?('/admin/') ? event_url : event_url.sub('/event/', '/admin/')
      page.goto(admin_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      # ログインリダイレクトされたら再ログイン
      if page.url.include?('login') || page.url.include?('signin')
        kokuchpro_ensure_login(page)
        page.goto(admin_url, waitUntil: 'domcontentloaded', timeout: 30_000)
        page.wait_for_timeout(2000)
      end

      log('[こくチーズ] 削除ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      deleted = page.evaluate(<<~'JS')
        (() => {
          const links = [...document.querySelectorAll('a, button, input[type="submit"]')];
          const del = links.find(el => /削除|delete/i.test(el.textContent || el.value || ''));
          if (del) { del.click(); return { found: true, text: (del.textContent || del.value || '').trim() }; }
          return { found: false, available: links.filter(el => el.offsetParent).slice(0, 15).map(el => (el.textContent || '').trim().substring(0, 30)) };
        })()
      JS

      if deleted['found']
        log("[こくチーズ] 「#{deleted['text']}」クリック")
        page.wait_for_timeout(3000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい"), a:has-text("削除")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[こくチーズ] ✅ イベント削除完了')
      else
        log("[こくチーズ] 利用可能なボタン: #{deleted['available']&.reject(&:blank?)&.join(', ')}")
        raise '[こくチーズ] 削除ボタンが見つかりません'
      end
    end

    def perform_cancel(page, event_url)
      kokuchpro_ensure_login(page)
      admin_url = event_url.include?('/admin/') ? event_url : event_url.sub('/event/', '/admin/')
      page.goto(admin_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      if page.url.include?('login') || page.url.include?('signin')
        kokuchpro_ensure_login(page)
        page.goto(admin_url, waitUntil: 'domcontentloaded', timeout: 30_000)
        page.wait_for_timeout(2000)
      end

      log('[こくチーズ] 中止ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      cancelled = page.evaluate(<<~'JS')
        (() => {
          const links = [...document.querySelectorAll('a, button')];
          const btn = links.find(el => /中止|キャンセル|cancel/i.test(el.textContent));
          if (btn) { btn.click(); return { found: true, text: btn.textContent.trim() }; }
          return { found: false };
        })()
      JS

      if cancelled['found']
        log("[こくチーズ] 「#{cancelled['text']}」クリック")
        page.wait_for_timeout(3000)
        confirm = page.locator('button:has-text("中止"), button:has-text("OK"), button:has-text("はい")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[こくチーズ] ✅ イベント中止完了')
      else
        raise '[こくチーズ] 中止ボタンが見つかりません'
      end
    end

    def kokuchpro_ensure_login(page)
      page.goto('https://www.kokuchpro.com/auth/login/', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(1000)
      return unless page.url.include?('login') || page.url.include?('signin')
      creds = ServiceConnection.credentials_for('kokuchpro')
      page.fill('#LoginFormEmail', creds[:email])
      page.fill('#LoginFormPassword', creds[:password])
      page.click('#UserLoginForm button[type="submit"]') rescue nil
      page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
      page.wait_for_timeout(2000)
      log('[こくチーズ] ✅ ログイン完了')
    end
  end
end
