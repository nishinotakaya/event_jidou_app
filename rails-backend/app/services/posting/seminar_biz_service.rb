module Posting
  class SeminarBizService < BaseService
    LOGIN_URL  = 'https://seminar-biz.com/company/login'
    CREATE_URL = 'https://seminar-biz.com/company/seminars/create'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_seminar(page, content, ef)
    end

    def ensure_login(page)
      log('[セミナーBiZ] ログインページへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      if page.url.include?('/dashboard') || page.url.include?('/seminars')
        log('[セミナーBiZ] ✅ ログイン済み')
        return
      end

      creds = ServiceConnection.credentials_for('seminar_biz')
      raise '[セミナーBiZ] メールアドレスが未設定です' if creds[:email].blank?

      page.fill('#email', creds[:email])
      page.fill('#password', creds[:password])
      page.locator('button[type="submit"]').first.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      raise '[セミナーBiZ] ログイン失敗' if page.url.include?('/login')
      log("[セミナーBiZ] ✅ ログイン完了 → #{page.url}")
    end

    def create_seminar(page, content, ef)
      log('[セミナーBiZ] セミナー作成ページへ移動...')
      page.goto(CREATE_URL, waitUntil: 'networkidle', timeout: 30_000) rescue page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # プラン制限チェック
      plan_limit = page.evaluate('document.body?.innerText?.includes("掲載上限数") || false') rescue false
      if plan_limit
        plan_msg = page.evaluate('(() => { const m = document.body.innerText.match(/現在契約中の[^。]+。/); return m ? m[0] : null; })()') rescue nil
        raise "[セミナーBiZ] 💰 プラン制限: #{plan_msg || 'フリープランの掲載上限に達しています'}。有料プラン(月5,500円〜)へのアップグレードが必要です。"
      end

      # リダイレクトされた場合は再ログイン＆リトライ
      unless page.url.include?('/create')
        log("[セミナーBiZ] ⚠️ 作成ページにリダイレクトされず（#{page.url}）→ 再ログイン後にリトライ")
        ensure_login(page)
        page.goto(CREATE_URL, waitUntil: 'networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)

        # 再度プラン制限チェック
        plan_limit2 = page.evaluate('document.body?.innerText?.includes("掲載上限数") || false') rescue false
        if plan_limit2
          plan_msg2 = page.evaluate('(() => { const m = document.body.innerText.match(/現在契約中の[^。]+。/); return m ? m[0] : null; })()') rescue nil
          raise "[セミナーBiZ] 💰 プラン制限: #{plan_msg2 || 'フリープランの掲載上限に達しています'}。有料プラン(月5,500円〜)へのアップグレードが必要です。"
        end

        unless page.url.include?('/create')
          raise "[セミナーBiZ] 作成ページにアクセスできません（URL: #{page.url}）"
        end
      end

      title_text = extract_title(ef, content, 100)
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      start_time = pad_time(ef['startTime'])
      end_time   = pad_time(ef['endTime'])
      sh, sm = start_time.split(':')
      eh, em = end_time.split(':')
      today = Date.today.strftime('%Y-%m-%d')

      # ===== タイトル [必須] =====
      page.fill('#title', title_text)
      log("[セミナーBiZ] タイトル: #{title_text}")

      # ===== ターゲット [必須] =====
      page.locator('input[name="target_type"][value="個人（スキルアップ）"], input[name="target_type"]').first.click rescue nil
      log('[セミナーBiZ] ターゲット: 個人（スキルアップ）')

      # ===== テーマ [必須] =====
      page.select_option('#theme', label: '(未選択)') rescue nil
      # ITに近いテーマを探す
      page.evaluate(<<~JS)
        (() => {
          const sel = document.getElementById('theme');
          const opts = Array.from(sel.options);
          const it = opts.find(o => o.text.includes('IT') || o.text.includes('テクノロジ'));
          if (it) { sel.value = it.value; }
          else { sel.selectedIndex = 1; }
          sel.dispatchEvent(new Event('change', { bubbles: true }));
        })()
      JS
      page.wait_for_timeout(500)
      log('[セミナーBiZ] テーマ選択完了')

      # ===== カバー画像 [必須] =====
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        page.locator('#cover_image').set_input_files(ef['imagePath'])
        page.wait_for_timeout(2000)
        log('[セミナーBiZ] カバー画像アップロード完了')
      else
        log('[セミナーBiZ] ⚠️ カバー画像なし（DALL-E画像生成をONにしてください）')
      end

      # ===== セミナー概要 [必須] =====
      plain_content = content.gsub(/<[^>]+>/, '').strip
      page.fill('#description', plain_content)
      log('[セミナーBiZ] セミナー概要入力完了')

      # ===== こんな人にオススメ =====
      page.fill('#requirement', "プログラミング・IT初心者の方\n副業・転職でスキルアップしたい方\nAI・最新技術に興味がある方") rescue nil

      # ===== 開催日 [必須] =====
      page.fill('#event_date', start_date)
      log("[セミナーBiZ] 開催日: #{start_date}")

      # ===== 開始時間 [必須] =====
      page.select_option('#event_start_hour', value: sh.to_i.to_s.rjust(2, '0'))
      page.select_option('#event_start_minute', value: sm.to_i.to_s.rjust(2, '0'))
      log("[セミナーBiZ] 開始時間: #{start_time}")

      # ===== 終了時間 [必須] =====
      page.select_option('#event_finish_hour', value: eh.to_i.to_s.rjust(2, '0'))
      page.select_option('#event_finish_minute', value: em.to_i.to_s.rjust(2, '0'))
      log("[セミナーBiZ] 終了時間: #{end_time}")

      # ===== 開場時間 =====
      # 開始15分前
      door_h = sh.to_i
      door_m = sm.to_i - 15
      if door_m < 0
        door_m += 60
        door_h -= 1
      end
      page.select_option('#doors_open_hour', value: door_h.to_s.rjust(2, '0')) rescue nil
      page.select_option('#doors_open_minute', value: door_m.to_s.rjust(2, '0')) rescue nil

      # ===== 募集期間 [必須] =====
      page.fill('#application_start_date', today)
      page.fill('#application_end_date', start_date)
      log("[セミナーBiZ] 募集期間: #{today} 〜 #{start_date}")

      # ===== 定員 [必須] =====
      capacity = ef['capacity'].presence || '50'
      page.fill('#capacity', capacity)
      log("[セミナーBiZ] 定員: #{capacity}")

      # ===== 参加費用 [必須] =====
      page.fill('#price', '0')
      log('[セミナーBiZ] 参加費: 無料')

      # ===== オンライン開催 [必須] =====
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        page.locator('#is_online_yes').click
        page.wait_for_timeout(1000)
        log('[セミナーBiZ] オンライン開催: はい')

        # 都道府県: オンライン
        page.select_option('#venue_prefecture', label: 'オンライン') rescue nil
        page.wait_for_timeout(500)

        # 会場名・住所はオンライン時disabledなのでJS経由で設定
        page.evaluate(<<~JS)
          (() => {
            const vn = document.getElementById('venue_name');
            const va = document.getElementById('venue_address');
            if (vn) { vn.disabled = false; vn.value = 'オンライン（Zoom）'; vn.dispatchEvent(new Event('input', {bubbles:true})); }
            if (va) { va.disabled = false; va.value = 'オンライン開催'; va.dispatchEvent(new Event('input', {bubbles:true})); }
          })()
        JS

        # オンラインURL [必須]
        zoom_url = ef['zoomUrl'].presence || 'https://zoom.us/'
        page.fill('#online_url', zoom_url)
        log("[セミナーBiZ] オンラインURL: #{zoom_url}")

        # オンライン参加方法
        zoom_id = ef['zoomId'].presence
        zoom_passcode = ef['zoomPasscode'].presence
        access_info = "Zoomで参加できます。"
        access_info += "\nミーティングID: #{zoom_id}" if zoom_id
        access_info += "\nパスコード: #{zoom_passcode}" if zoom_passcode
        page.fill('#online_access', access_info) rescue nil
      else
        page.locator('#is_online_no').click
        page.wait_for_timeout(1000)
        page.fill('#venue_name', place)
        page.select_option('#venue_prefecture', label: '東京都') rescue nil
        page.fill('#venue_address', place) rescue nil
      end

      # ===== 連絡先 =====
      tel = ef['tel'].presence || ''
      page.fill('#contact_info', tel) if tel.present?

      # ===== 公開ステータス =====
      if ef.dig('publishSites', 'セミナーBiZ')
        page.locator('#is_public_yes').click
        log('[セミナーBiZ] 公開ステータス: 公開')
      else
        page.locator('#is_public_no').click
        log('[セミナーBiZ] 公開ステータス: 非公開')
      end

      # ===== 保存ボタン =====
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
      page.wait_for_timeout(1000)

      # 「作成」ボタン（ログアウトボタンと区別するため、フォーム内のsubmitを正確に指定）
      save_btn = page.locator('button[type="submit"]:has-text("作成")').first
      unless (save_btn.visible?(timeout: 5000) rescue false)
        save_btn = page.locator('button:has-text("保存"), button:has-text("登録")').first
      end
      raise '[セミナーBiZ] 保存ボタンが見つかりません' unless (save_btn.visible?(timeout: 3000) rescue false)

      save_btn.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      # 保存成功の確認（URLが変わっていればOK）
      if page.url.include?('/create')
        # バリデーションエラーを確認
        errors = page.evaluate(<<~JS) rescue []
          (() => {
            const els = document.querySelectorAll('.text-red-500, .text-danger, .error, [role=alert]');
            return Array.from(els).map(el => el.textContent.trim()).filter(t => t.length > 0 && t.length < 200);
          })()
        JS
        if errors.any?
          log("[セミナーBiZ] ⚠️ バリデーションエラー: #{errors.first(3).join(', ')}")
          raise "[セミナーBiZ] 保存失敗: #{errors.first}"
        end
      end

      # セミナー一覧からイベントURLを取得
      page.goto('https://seminar-biz.com/company/seminars', waitUntil: 'domcontentloaded', timeout: 15_000) rescue nil
      page.wait_for_timeout(2000)
      event_url = page.evaluate(<<~JS) rescue nil
        (() => {
          const a = document.querySelector('a[href*="/seminar/"][href*="/events/"]');
          return a ? a.href.replace('?preview=1', '') : null;
        })()
      JS
      if event_url
        log("[セミナーBiZ] ✅ セミナー作成完了 → #{event_url}")
      else
        log("[セミナーBiZ] ✅ セミナー作成完了 → #{page.url}")
      end
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      # マイページ → セミナー管理一覧から操作
      page.goto('https://seminar-biz.com/company/seminars', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[セミナーBiZ] セミナー管理画面で削除中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil

      # event_urlからIDを抽出
      event_id = event_url[/events\/(\d+)/, 1]

      # 削除ボタンを探す（一覧 or 詳細ページ）
      del_btn = page.locator("a[href*=\"#{event_id}\"][href*=\"delete\"], button:has-text(\"削除\"), a:has-text(\"削除\")").first
      if (del_btn.visible?(timeout: 5000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[セミナーBiZ] ✅ イベント削除完了')
      else
        # 個別ページに遷移して削除
        edit_url = event_url.sub('?preview', '') + '/edit'
        page.goto(edit_url, waitUntil: 'domcontentloaded', timeout: 30_000) rescue nil
        page.wait_for_timeout(2000)
        page.evaluate('() => window.scrollTo(0, document.body.scrollHeight)')
        page.wait_for_timeout(1000)
        del2 = page.locator('button:has-text("削除"), a:has-text("削除")').first
        if (del2.visible?(timeout: 3000) rescue false)
          del2.click
          page.wait_for_timeout(3000)
          log('[セミナーBiZ] ✅ 編集ページから削除完了')
        else
          raise '[セミナーBiZ] 削除ボタンが見つかりません'
        end
      end
    end

    def perform_cancel(page, event_url)
      # セミナーBiZはedit画面から非公開に変更
      ensure_login(page)
      edit_url = event_url.sub('?preview', '') + '/edit'
      page.goto(edit_url, waitUntil: 'domcontentloaded', timeout: 30_000) rescue nil
      page.wait_for_timeout(2000)

      if page.url.include?('/edit')
        log('[セミナーBiZ] 非公開に変更中...')
        no_btn = page.locator('#is_public_no').first
        if (no_btn.visible?(timeout: 3000) rescue false)
          no_btn.click
          page.wait_for_timeout(500)
          save = page.locator('button[type="submit"]:has-text("保存"), button[type="submit"]:has-text("更新")').first
          save.click if (save.visible?(timeout: 3000) rescue false)
          page.wait_for_timeout(3000)
          log('[セミナーBiZ] ✅ 非公開に変更完了')
        else
          raise '[セミナーBiZ] 非公開ボタンが見つかりません'
        end
      else
        raise '[セミナーBiZ] 編集ページに遷移できません'
      end
    end
  end
end
