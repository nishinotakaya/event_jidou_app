module Posting
  class JimotyService < BaseService
    LOGIN_URL  = 'https://jmty.jp/users/sign_in'
    CREATE_URL = 'https://jmty.jp/articles/new'

    private

    def execute(page, content, ef)
      ensure_login(page)
      create_event(page, content, ef)
    end

    def ensure_login(page)
      log('[ジモティー] ログインページへ移動...')
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      if page.url.include?('/my/') || (page.text_content('body').to_s.include?('ログアウト') rescue false)
        log('[ジモティー] ✅ ログイン済み')
        return
      end

      creds = ServiceConnection.credentials_for('jimoty')
      raise '[ジモティー] メールアドレスが未設定です' if creds[:email].blank?

      page.fill('input[name="user[email]"]', creds[:email])
      page.fill('input[name="user[password]"]', creds[:password])
      page.locator('input[type="submit"]').first.click
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.wait_for_timeout(3000)

      if page.url.include?('/sign_in')
        raise '[ジモティー] ログイン失敗'
      end
      log("[ジモティー] ✅ ログイン完了 → #{page.url}")
    end

    def create_event(page, content, ef)
      log('[ジモティー] 投稿フォームへ移動...')
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(2000)

      title_text = extract_title(ef, content, 80)

      # 大カテゴリ: イベント (value=2)
      page.select_option('#category_group_id', value: '2')
      page.wait_for_timeout(2000)
      log('[ジモティー] カテゴリ: イベント')

      # サブカテゴリ: セミナー (value=22)
      page.select_option('#article_category_id', value: '22')
      page.wait_for_timeout(500)
      log('[ジモティー] サブカテゴリ: セミナー')

      # 都道府県: 千葉県
      page.select_option('#article_prefecture_id', label: '千葉県') rescue nil
      page.wait_for_timeout(2000)
      log('[ジモティー] 都道府県: 千葉県')

      # 市区町村: 松戸市
      page.select_option('#article_city_id', label: '松戸市') rescue nil
      page.wait_for_timeout(1000)
      log('[ジモティー] 市区町村: 松戸市')

      # タイトル
      page.fill('#article_title', title_text)
      log("[ジモティー] タイトル: #{title_text}")

      # 本文
      plain_content = content.gsub(/<[^>]+>/, '').strip
      page.fill('#article_text', plain_content)
      log('[ジモティー] 本文入力完了')

      # 開催日（必須）— format: YYYY/MM/DD
      start_date = normalize_date(ef['startDate'].presence || default_date_plus(30))
      event_date_slash = start_date.gsub('-', '/')
      page.fill('#article_date', event_date_slash)
      log("[ジモティー] 開催日: #{event_date_slash}")

      # 終了日
      end_date = ef['endDate'].presence || ef['startDate'].presence
      if end_date.present?
        end_date_slash = normalize_date(end_date).gsub('-', '/')
        page.fill('#article_end_date', end_date_slash)
        log("[ジモティー] 終了日: #{end_date_slash}")
      end

      # 募集期限（開催日の前日）
      begin
        deadline = (Date.parse(start_date) - 1).strftime('%Y/%m/%d')
        page.fill('#article_deadline', deadline)
        log("[ジモティー] 募集期限: #{deadline}")
      rescue
      end

      # 開催場所
      place = ef['place'].presence || 'オンライン'
      page.fill('#article_address', place)
      log("[ジモティー] 開催場所: #{place}")

      # 画像アップロード
      if ef['imagePath'].present? && File.exist?(ef['imagePath'].to_s)
        file_input = page.locator('input[type="file"]').first
        if (file_input.count > 0 rescue false)
          file_input.set_input_files(ef['imagePath'])
          page.wait_for_timeout(3000)
          log('[ジモティー] 画像アップロード完了')
        end
      end

      # 投稿ボタン
      page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
      page.wait_for_timeout(500)

      submit_btn = page.locator('#article_submit_button, input[type="submit"]').first
      if (submit_btn.visible?(timeout: 3000) rescue false)
        submit_btn.click
        page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
        page.wait_for_timeout(3000)

        # 確認画面がある場合
        confirm_btn = page.locator('input[type="submit"], button:has-text("投稿する"), button:has-text("確定")').first
        if (confirm_btn.visible?(timeout: 3000) rescue false)
          confirm_btn.click
          page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
          page.wait_for_timeout(3000)
        end

        final_url = page.url
        # 完了ページのURLからイベントIDを抽出して記事URLを構築
        # 例: articles/complete?category_group_name=eve&category_name=work&id=1o3sx3&prefecture_name=chiba
        if final_url.include?('complete') && (m = final_url.match(/id=([^&]+)/))
          article_id = m[1]
          pref = final_url.match(/prefecture_name=([^&]+)/)&.[](1) || 'chiba'
          cat_group = final_url.match(/category_group_name=([^&]+)/)&.[](1) || 'eve'
          cat = final_url.match(/category_name=([^&]+)/)&.[](1) || 'work'
          article_url = "https://jmty.jp/#{pref}/#{cat_group}-#{cat}/article-#{article_id}/"
          log("[ジモティー] ✅ 投稿完了 → #{article_url}")
        else
          log("[ジモティー] ✅ 投稿完了 → #{final_url}")
        end
      else
        raise '[ジモティー] 投稿ボタンが見つかりません'
      end
    end
  end
end
