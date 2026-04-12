module Posting
  class StreetAcademyService < BaseService
    LOGIN_URL  = 'https://www.street-academy.com/d/users/sign_in'
    CREATE_URL = 'https://www.street-academy.com/myclass/new'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_lecture(page, content, ef)
    end

    def ensure_login(page)
      log('[ストアカ] ログイン状態を確認中...')
      page.goto('https://www.street-academy.com/dashboard/steachers/myclass', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      unless page.url.include?('/sign_in') || page.url.include?('/login')
        log("[ストアカ] ✅ ログイン済み → #{page.url}")
        return
      end

      log('[ストアカ] ログインページへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      creds = ServiceConnection.credentials_for('street_academy')
      raise '[ストアカ] メールアドレスが未設定です' if creds[:email].blank?

      page.fill('#user_email', creds[:email])
      page.fill('#user_password', creds[:password])
      page.click('input[type="submit"], button[type="submit"]')
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      if page.url.include?('/sign_in')
        page_text = page.evaluate("document.body?.innerText?.substring(0, 300) || ''") rescue ''
        raise "[ストアカ] ログイン失敗 (URL: #{page.url}, body: #{page_text[0, 100]})"
      end
      log("[ストアカ] ✅ ログイン完了 → #{page.url}")
    end

    def create_lecture(page, content, ef)
      log('[ストアカ] 講座作成ページへ移動...')
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # 開催形式
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        page.click('#is_online_check')
        log('[ストアカ] 開催形式: オンライン')
      else
        page.click('#is_offline_check')
        log('[ストアカ] 開催形式: 対面')
      end
      page.wait_for_timeout(2000)

      # 単発開催
      page.click('#class_detail_is_course_0')
      page.wait_for_timeout(1000)
      log('[ストアカ] 開催タイプ: 単発')

      # タイトル（最大33文字）
      title_text = extract_title(ef, content, 33)
      page.fill('#class_detail_classname', title_text)
      log("[ストアカ] タイトル: #{title_text}")

      # キャッチコピー（最大70文字）
      catchcopy = content.split("\n").find { |l| l.strip.length > 10 && !l.start_with?('#', '■', '【') }.to_s[0, 70]
      catchcopy = "#{title_text} - 初心者歓迎のオンライン講座" if catchcopy.blank?
      page.fill('#class_detail_class_catchcopy', catchcopy[0, 70])
      log("[ストアカ] キャッチコピー: #{catchcopy[0, 30]}...")

      # 教える内容
      plain_content = content.gsub(/<[^>]+>/, '').strip[0, 3500]
      page.fill('#class_detail_classdescription', plain_content)
      log('[ストアカ] 教える内容入力完了')

      # 対象者
      target_area = page.locator('#class_detail_class_requirement')
      if (target_area.visible?(timeout: 2000) rescue false)
        target_area.fill("プログラミング・IT初心者の方\n副業・転職でスキルアップしたい方\nAI・最新技術に興味がある方")
        log('[ストアカ] 対象者入力完了')
      end

      # 料金（最低1000円）
      cost_input = place.include?('オンライン') ?
        page.locator('#online-class-cost-form') :
        page.locator('#class-cost-form')
      if (cost_input.visible?(timeout: 2000) rescue false)
        cost_input.fill('1000')
        log('[ストアカ] 料金: 1000円')
      end

      # カテゴリー（「プログラミング」で検索 → IT・リスキリング > プログラミング）
      cat_input = page.locator('#set_category_on_class_detail')
      if (cat_input.visible?(timeout: 2000) rescue false)
        cat_input.fill('プログラミング')
        page.wait_for_timeout(2000)
        autocomplete = page.locator('.ui-autocomplete .ui-menu-item, .ui-autocomplete li').first
        autocomplete.click if (autocomplete.visible?(timeout: 3000) rescue false)
        log('[ストアカ] カテゴリー: IT・リスキリング > プログラミング')
        page.wait_for_timeout(500)
      end

      # 画像アップロード
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        file_input = page.locator('#mod-cropper_input-1')
        if (file_input.count > 0 rescue false)
          file_input.set_input_files(ef['imagePath'])
          page.wait_for_timeout(3000)
          crop_btn = page.locator('.cropper-submit, button:has-text("確定"), button:has-text("OK")').first
          crop_btn.click if (crop_btn.visible?(timeout: 3000) rescue false)
          page.wait_for_timeout(2000)
          log('[ストアカ] 画像アップロード完了')
        end
      end

      # 保存
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
      page.wait_for_timeout(1000)

      submit_btn = page.locator('button[type="submit"]').last
      if (submit_btn.visible?(timeout: 3000) rescue false)
        submit_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)

        saved_url = page.url
        class_url = saved_url
        if saved_url !~ %r{myclass/\d+}
          class_url = page.evaluate(<<~JS) rescue saved_url
            () => {
              const links = [...document.querySelectorAll('a[href*="/myclass/"]')];
              const match = links.find(a => /myclass\/\\d+/.test(a.href));
              return match ? match.href : location.href;
            }
          JS
        end
        log("[ストアカ] ✅ 講座保存完了 → #{class_url}")
      else
        raise '[ストアカ] 保存ボタンが見つかりません'
      end

      # 公開申請
      request_publish(page)
      log('[ストアカ] ✅ 処理完了（※講座公開にはストアカの審査が必要です）')
    end

    def request_publish(page)
      log('[ストアカ] 公開申請中...')

      # 「講座の公開を申請する」ボタン
      publish_btn = page.locator('#public_application_button')
      return unless (publish_btn.visible?(timeout: 5000) rescue false)

      publish_btn.click
      page.wait_for_timeout(3000)

      # モーダル内のチェックボックスにチェック
      page.evaluate(<<~JS)
        (() => {
          const cb1 = document.querySelector('#confirm_notice_prohibition');
          if (cb1 && !cb1.checked) cb1.click();
          const cb2 = document.querySelector('#confirm_notice_agreement');
          if (cb2 && !cb2.checked) cb2.click();
        })()
      JS
      page.wait_for_timeout(1000)

      # 公開申請ボタンをフォーム送信（data-method="put"のRails UJS対応）
      page.evaluate(<<~JS)
        (() => {
          const btn = document.querySelector('#dashboard-publish-notice-confirm');
          if (!btn) return;
          const href = btn.getAttribute('href');
          if (!href) return;
          const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || '';
          const csrfParam = document.querySelector('meta[name="csrf-param"]')?.content || 'authenticity_token';
          const form = document.createElement('form');
          form.method = 'POST';
          form.action = href;
          form.style.display = 'none';
          const m = document.createElement('input');
          m.type = 'hidden'; m.name = '_method'; m.value = 'put';
          form.appendChild(m);
          const t = document.createElement('input');
          t.type = 'hidden'; t.name = csrfParam; t.value = csrfToken;
          form.appendChild(t);
          document.body.appendChild(form);
          form.submit();
        })()
      JS
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)
      log("[ストアカ] 公開申請送信完了 → #{page.url}")
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[ストアカ] 削除ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      del_btn = page.locator('a:has-text("削除"), button:has-text("削除")').first
      if (del_btn.visible?(timeout: 5000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[ストアカ] ✅ イベント削除完了')
      else
        raise '[ストアカ] 削除ボタンが見つかりません'
      end
    end

    def perform_cancel(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[ストアカ] 非公開/中止処理中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      cancel_btn = page.locator('a:has-text("非公開"), button:has-text("非公開"), a:has-text("中止"), button:has-text("中止")').first
      if (cancel_btn.visible?(timeout: 5000) rescue false)
        cancel_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("非公開"), button:has-text("中止"), button:has-text("OK"), button:has-text("はい")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[ストアカ] ✅ 非公開/中止完了')
      else
        raise '[ストアカ] 非公開/中止ボタンが見つかりません'
      end
    end
  end
end
