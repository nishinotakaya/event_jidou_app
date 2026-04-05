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
      log('[ストアカ] ログインページへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      unless page.url.include?('/sign_in')
        log('[ストアカ] ✅ ログイン済み')
        return
      end

      creds = ServiceConnection.credentials_for('street_academy')
      raise '[ストアカ] メールアドレスが未設定です' if creds[:email].blank?

      page.fill('#user_email', creds[:email])
      page.fill('#user_password', creds[:password])
      page.click('input[type="submit"]')
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      if page.url.include?('/sign_in')
        raise '[ストアカ] ログイン失敗'
      end
      log("[ストアカ] ✅ ログイン完了 → #{page.url}")
    end

    def create_lecture(page, content, ef)
      log('[ストアカ] 講座作成ページへ移動...')
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(3000)

      # 開催形式: オンライン
      place = ef['place'].presence || 'オンライン'
      if place.include?('オンライン')
        online_radio = page.locator('#is_online_check')
        online_radio.click if (online_radio.visible?(timeout: 3000) rescue false)
        log('[ストアカ] 開催形式: オンライン')
      else
        offline_radio = page.locator('#is_offline_check')
        offline_radio.click if (offline_radio.visible?(timeout: 3000) rescue false)
        log('[ストアカ] 開催形式: 対面')
      end
      page.wait_for_timeout(1000)

      # 単発開催
      single = page.locator('#class_detail_is_course_0')
      single.click if (single.visible?(timeout: 2000) rescue false)
      log('[ストアカ] 開催タイプ: 単発')

      # エリア（オンラインの場合も東京を選択）
      prefecture_select = page.locator('#class_detail_prefecture')
      if (prefecture_select.visible?(timeout: 2000) rescue false)
        prefecture_select.select_option(label: '東京都') rescue nil
        page.wait_for_timeout(1000)
        log('[ストアカ] エリア: 東京都')
      end

      # タイトル
      title_text = extract_title(ef, content, 33)
      title_input = page.locator('#class_detail_classname')
      if (title_input.visible?(timeout: 3000) rescue false)
        title_input.fill(title_text)
        log("[ストアカ] タイトル: #{title_text}")
      end

      # キャッチコピー
      catchcopy = content.split("\n").find { |l| l.strip.length > 10 && !l.start_with?('#', '■', '【') }.to_s[0, 70]
      catchcopy = "#{title_text} - 初心者歓迎のオンライン講座" if catchcopy.blank?
      catch_input = page.locator('#class_detail_class_catchcopy')
      if (catch_input.visible?(timeout: 2000) rescue false)
        catch_input.fill(catchcopy)
        log("[ストアカ] キャッチコピー: #{catchcopy[0, 30]}...")
      end

      # 教える内容（説明文）
      desc_area = page.locator('#class_detail_classdescription')
      if (desc_area.visible?(timeout: 3000) rescue false)
        # HTMLタグを除去してプレーンテキストで入力
        plain_content = content.gsub(/<[^>]+>/, '').strip[0, 3500]
        desc_area.fill(plain_content)
        log('[ストアカ] 教える内容入力完了')
      end

      # 対象者
      target_area = page.locator('#class_detail_class_requirement')
      if (target_area.visible?(timeout: 2000) rescue false)
        target_area.fill("プログラミング・IT初心者の方\n副業・転職でスキルアップしたい方\nAI・最新技術に興味がある方")
        log('[ストアカ] 対象者入力完了')
      end

      # 料金（無料 → 1000円が最低）
      cost_input = place.include?('オンライン') ?
        page.locator('#online-class-cost-form') :
        page.locator('#class-cost-form')
      if (cost_input.visible?(timeout: 2000) rescue false)
        cost_input.fill('1000')
        log('[ストアカ] 料金: 1000円')
      end

      # カテゴリー（IT・リスキリング）
      cat_input = page.locator('#set_category_on_class_detail')
      if (cat_input.visible?(timeout: 2000) rescue false)
        cat_input.fill('IT')
        page.wait_for_timeout(1500)
        autocomplete = page.locator('.ui-autocomplete .ui-menu-item').first
        autocomplete.click if (autocomplete.visible?(timeout: 3000) rescue false)
        log('[ストアカ] カテゴリー: IT・リスキリング')
        page.wait_for_timeout(500)
      end

      # 画像アップロード
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        file_input = page.locator('#mod-cropper_input-1')
        if (file_input.count > 0 rescue false)
          file_input.set_input_files(ef['imagePath'])
          page.wait_for_timeout(3000)
          # クロッパーモーダルの確認ボタン
          crop_btn = page.locator('.cropper-submit, button:has-text("確定"), button:has-text("OK")').first
          crop_btn.click if (crop_btn.visible?(timeout: 3000) rescue false)
          page.wait_for_timeout(2000)
          log('[ストアカ] 画像アップロード完了')
        end
      end

      # プレビュー（保存）
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
      page.wait_for_timeout(1000)

      submit_btn = page.locator('button[type="submit"], input[type="submit"]').last
      if (submit_btn.visible?(timeout: 3000) rescue false)
        submit_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)
        # 保存後のURLからクラスIDを取得
        saved_url = page.url
        class_url = saved_url
        # myclass/XXX パターンのURLを探す
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

      log('[ストアカ] ✅ 処理完了（※講座公開にはストアカの審査が必要です）')
    end

    # --- 削除・中止 ---

    def perform_delete(page, event_url)
      ensure_login(page)
      page.goto(event_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      log('[ストアカ] 削除ボタンを探索中...')
      page.on('dialog', ->(d) { d.accept }) rescue nil
      del_btn = page.locator('a:has-text("削除"), button:has-text("削除"), a:has-text("Delete"), button:has-text("Delete")').first
      if (del_btn.visible?(timeout: 5000) rescue false)
        del_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("削除"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes"), button:has-text("Delete")').first
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
      cancel_btn = page.locator('a:has-text("非公開"), button:has-text("非公開"), a:has-text("中止"), button:has-text("中止"), a:has-text("キャンセル"), button:has-text("Cancel")').first
      if (cancel_btn.visible?(timeout: 5000) rescue false)
        cancel_btn.click
        page.wait_for_timeout(2000)
        confirm = page.locator('button:has-text("非公開"), button:has-text("中止"), button:has-text("OK"), button:has-text("はい"), button:has-text("Yes")').first
        confirm.click if (confirm.visible?(timeout: 3000) rescue false)
        page.wait_for_timeout(3000)
        log('[ストアカ] ✅ 非公開/中止完了')
      else
        raise '[ストアカ] 非公開/中止ボタンが見つかりません'
      end
    end
  end
end
