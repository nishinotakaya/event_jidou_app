module Posting
  class OnclassService < BaseService
    BASE_URL = 'https://manager.the-online-class.com'.freeze

    CHANNELS = [
      '全体チャンネル',
      'もくもく会',
      '人工インターン - チーム【フリーエンジニア養成コース】',
      '勤怠A - 報告',
      '勤怠B - 報告',
      '勤怠a-ポートチーム5【フリーエンジニア養成コース】',
      'PDCAアプリ開発',
      'TodoB - 質問',
      'TodoB - 報告',
      'TodoA - 質問',
      'TodoA - 報告',
      'クローンチーム',
      'Aチーム（元基礎編）',
      'Bチーム（元Todo）',
      'TechPutチーム',
    ].freeze

    private

    def execute(page, content, ef)
      channels = parse_channels(ef)
      raise '[オンクラス] チャンネルが選択されていません' if channels.empty?

      @image_path = ef['onclassImagePath'].presence || ef['imagePath'].presence

      ensure_login(page)

      # メンション対象: UIから渡された場合はそれを使用、なければ自動取得
      mention_names = parse_mentions(ef)
      if mention_names.empty?
        mention_names = fetch_frontend_students(page)
      end
      log("[オンクラス] メンション対象: #{mention_names.length}名")

      navigate_to_community(page)

      channels.each do |channel|
        log("[オンクラス] チャンネル「#{channel}」にメッセージ送信中...")
        select_channel(page, channel)
        send_message_with_mentions(page, content, mention_names)
        log("[オンクラス] ✅ チャンネル「#{channel}」送信完了")
      end

      log("[オンクラス] ✅ 全#{channels.length}チャンネルへの送信完了")
    end

    def ensure_login(page)
      creds = ServiceConnection.credentials_for('onclass')
      email = creds[:email].presence || 'takaya314boxing@gmail.com'
      password = creds[:password].presence || 'takaya314'

      page.goto("#{BASE_URL}/sign_in", timeout: 30_000, waitUntil: 'load')
      page.wait_for_timeout(3000)

      # 既にログイン済みかチェック
      return log('[オンクラス] ✅ ログイン済み') unless page.url.include?('sign_in')

      page.fill('input[name="email"]', email)
      page.fill('input[name="password"]', password)
      page.locator('button:has-text("ログインする")').click
      page.wait_for_timeout(5000)

      raise '[オンクラス] ログイン失敗 — sign_inページのまま' if page.url.include?('sign_in')
      log('[オンクラス] ✅ ログイン完了')
    end

    def navigate_to_community(page)
      page.goto("#{BASE_URL}/community", timeout: 30_000, waitUntil: 'load')
      page.wait_for_timeout(3000)

      # サイドバーの「コミュニティ」をクリックしてコミュニティビューを確実に開く
      page.evaluate(<<~JS)
        (() => {
          const items = [...document.querySelectorAll('.v-list-item')];
          const comm = items.find(el => {
            const t = el.querySelector('.v-list-item-title');
            return t && t.textContent.trim() === 'コミュニティ';
          });
          if (comm) comm.click();
        })()
      JS
      page.wait_for_timeout(5000)

      # コミュニティのチャンネルリストが表示されるまで待機
      10.times do
        has_channels = page.evaluate(<<~JS) rescue false
          (() => {
            const items = [...document.querySelectorAll('.v-list-item')];
            return items.some(el => {
              const t = (el.querySelector('.v-list-item-title')?.textContent || el.textContent || '').trim();
              return t.includes('チーム') || t.includes('チャンネル') || t.includes('もくもく') || t.includes('報告') || t.includes('質問');
            });
          })()
        JS
        break if has_channels
        page.wait_for_timeout(2000)
      end
      log('[オンクラス] コミュニティページに移動')
    end

    def select_channel(page, channel_name)
      escaped = channel_name.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")
      clicked = page.evaluate(<<~JS)
        (() => {
          const name = '#{escaped}';
          const items = [...document.querySelectorAll('.v-list-item')];
          let target = items.find(el => {
            const title = el.querySelector('.v-list-item-title');
            return (title && title.textContent.trim() === name) || el.textContent.trim() === name;
          });
          if (!target) {
            target = items.find(el => {
              const text = (el.querySelector('.v-list-item-title')?.textContent || el.textContent || '').trim();
              return text.includes(name) || name.includes(text.split('\\n')[0]);
            });
          }
          if (target) {
            target.scrollIntoView({ block: 'center', behavior: 'instant' });
            target.click();
            return true;
          }
          return false;
        })()
      JS

      unless clicked
        avail = page.evaluate(<<~JS) rescue '[]'
          JSON.stringify([...document.querySelectorAll('.v-list-item')].map(el =>
            (el.querySelector('.v-list-item-title')?.textContent || el.textContent || '').trim().substring(0, 40)
          ).filter(t => !['ホーム','コース管理','従業員管理','システム設定','マーケティング','コンテンツ','LP構築'].some(n => t.startsWith(n))))
        JS
        log("[オンクラス] 利用可能チャンネル: #{avail}")
        raise "[オンクラス] チャンネル「#{channel_name}」が見つかりません"
      end
      page.wait_for_timeout(3000)
    end

    def send_message_with_mentions(page, content, mention_names)
      textarea = page.locator('textarea.v-field__input').first
      textarea.click
      page.wait_for_timeout(500)

      # メンションを1人ずつ追加（@名前 → 候補絞り込み → クリックで確定）
      mention_names.each_with_index do |name, idx|
        # オーバーレイが開いていたら閉じる
        page.keyboard.press('Escape') rescue nil
        page.wait_for_timeout(300)

        # @と名前を入力して候補を絞り込む
        textarea.click
        page.wait_for_timeout(200)
        textarea.type("@#{name}")
        page.wait_for_timeout(2500)

        # オートコンプリート候補をクリック
        escaped = name.gsub('"', '\\"')
        candidate = page.locator(".v-overlay .v-list-item:has-text(\"#{escaped}\")").first
        selected = begin
          if candidate.visible?(timeout: 3000)
            candidate.click
            page.wait_for_timeout(800)
            true
          else
            false
          end
        rescue
          false
        end

        unless selected
          log("[オンクラス] ⚠️ メンション候補なし: #{name}")
          # 入力済みの@名前をBackspaceで消す
          (name.length + 1).times { page.keyboard.press('Backspace') }
          page.wait_for_timeout(300)
        end

        # 次のメンションとの区切り
        textarea.type(' ') if idx < mention_names.length - 1
        page.wait_for_timeout(300)

        log("[オンクラス] メンション追加: @#{name} (#{idx + 1}/#{mention_names.length})") if (idx + 1) % 5 == 0 || idx == mention_names.length - 1
      end

      # メッセージ本文を入力
      page.keyboard.press('Escape') rescue nil
      page.wait_for_timeout(300)
      textarea.type("\n#{content}")
      page.wait_for_timeout(1000)

      # 画像添付（1枚）
      image_path = @image_path
      if image_path.present? && File.exist?(image_path.to_s)
        file_input = page.locator('input[type="file"]').first
        file_input.set_input_files(image_path)
        page.wait_for_timeout(3000)
        log('[オンクラス] 📷 画像添付完了')
      end

      # 送信ボタン（↑アイコン）をクリック
      send_icon = page.locator('i.mdi-arrow-up-box, [class*="_send_icon_"]').first
      send_icon.click(force: true)
      page.wait_for_timeout(3000)
    end

    def fetch_frontend_students(page)
      # 従業員一覧ページでフロントエンジニアコースをフィルタ
      page.goto("#{BASE_URL}/accounts", timeout: 30_000, waitUntil: 'load')
      page.wait_for_timeout(8000)

      # コースセレクトを開く（force: trueでクリック）
      select_field = page.locator('.v-select .v-field').first
      select_field.click(force: true)
      page.wait_for_timeout(3000)

      # フロントエンジニアコースを選択
      course_item = page.locator('.v-overlay .v-list-item:has-text("フロントエンジニアコース")').first
      course_item.click
      page.wait_for_timeout(2000)

      # 検索ボタンをクリック
      page.evaluate(<<~JS)
        (() => {
          const btns = [...document.querySelectorAll('button')];
          const searchBtn = btns.find(b => b.textContent.trim() === '従業員検索');
          if (searchBtn) searchBtn.click();
        })()
      JS
      page.wait_for_timeout(8000)

      # 全ページから名前を収集（span._user_name_* セレクタ）
      names = []
      loop do
        page_names = page.evaluate(<<~JS)
          (() => {
            const spans = document.querySelectorAll('span[class*="_user_name_"]');
            return [...spans].map(s => s.textContent.trim()).filter(n => n.length > 0);
          })()
        JS
        names.concat(page_names) if page_names.is_a?(Array)

        # 次ページへ（ページ番号ボタンをクリック）
        has_next = page.evaluate(<<~JS)
          (() => {
            const pagBtns = [...document.querySelectorAll('.v-pagination button')];
            const activeIdx = pagBtns.findIndex(b => b.getAttribute('aria-current') === 'true');
            if (activeIdx >= 0 && activeIdx < pagBtns.length - 1) {
              const nextBtn = pagBtns[activeIdx + 1];
              if (!nextBtn.disabled && nextBtn.textContent.trim().match(/^\\d+$/)) {
                nextBtn.click();
                return true;
              }
            }
            return false;
          })()
        JS
        break unless has_next
        page.wait_for_timeout(5000)
      end

      log("[オンクラス] フロントコース受講生一覧取得完了: #{names.uniq.length}名")
      names.uniq
    end

    def check_mentions(page)
      ensure_login(page)
      navigate_to_community(page)

      # メンションタブをクリック
      page.evaluate(<<~JS)
        (() => {
          const items = [...document.querySelectorAll('.v-list-item')];
          const mention = items.find(el => el.textContent.trim().startsWith('メンション'));
          if (mention) { mention.scrollIntoView({ block: 'center' }); mention.click(); }
        })()
      JS
      page.wait_for_timeout(3000)

      # メンション一覧を取得
      page.evaluate(<<~JS)
        (() => {
          const results = [];
          document.querySelectorAll('[class*="message"]').forEach(el => {
            const text = el.textContent.trim();
            if (text) results.push(text.substring(0, 200));
          });
          return results;
        })()
      JS
    end

    def parse_mentions(ef)
      raw = ef['onclassMentions']
      case raw
      when Array then raw.select { |n| n.is_a?(String) && n.present? }
      else []
      end
    end

    def parse_channels(ef)
      raw = ef['onclassChannels']
      case raw
      when Array then raw
      when String then raw.split(',').map(&:strip).reject(&:empty?)
      else ['全体チャンネル']
      end
    end

    def perform_delete(_page, _event_url)
      log('[オンクラス] 削除操作は未対応です')
    end

    def perform_cancel(_page, _event_url)
      log('[オンクラス] 中止操作は未対応です')
    end
  end
end
