module Posting
  class BaseService
    def call(page, content, event_fields = {}, &log_callback)
      @log_callback = log_callback
      execute(page, content, event_fields)
    end

    # リモートイベント更新（既存投稿の内容を編集）
    def update_remote(page, event_url, content, event_fields = {}, &log_callback)
      @log_callback = log_callback
      perform_update(page, event_url, content, event_fields)
    end

    # リモートイベント削除
    def delete_remote(page, event_url, &log_callback)
      @log_callback = log_callback
      perform_delete(page, event_url)
    end

    # リモートイベント中止
    def cancel_remote(page, event_url, &log_callback)
      @log_callback = log_callback
      perform_cancel(page, event_url)
    end

    # リモートイベント公開
    def publish_remote(page, event_url, &log_callback)
      @log_callback = log_callback
      perform_publish(page, event_url)
    end

    private

    def perform_update(_page, _event_url, _content, _event_fields)
      raise NotImplementedError, "#{self.class.name}#perform_update is not implemented"
    end

    def perform_delete(_page, _event_url)
      raise NotImplementedError, "#{self.class.name}#perform_delete is not implemented"
    end

    def perform_cancel(_page, _event_url)
      raise NotImplementedError, "#{self.class.name}#perform_cancel is not implemented"
    end

    def perform_publish(page, event_url)
      page.goto(event_url, timeout: 30_000, waitUntil: 'domcontentloaded')
      page.wait_for_timeout(3000)

      # 汎用公開ボタン検索
      publish_selectors = [
        'button:has-text("公開する")', 'button:has-text("公開")',
        'button:has-text("掲載する")', 'button:has-text("掲載")',
        'a:has-text("公開する")', 'a:has-text("公開")',
        'input[value="公開する"]', 'input[value="公開"]',
      ]
      published = false
      publish_selectors.each do |sel|
        btn = page.locator(sel).first
        next unless (btn.visible?(timeout: 1000) rescue false)
        btn.click
        page.wait_for_timeout(2000)
        # 確認ダイアログ
        %w[はい OK 公開する 確認].each do |confirm_text|
          confirm_btn = page.locator("button:has-text(\"#{confirm_text}\")").first
          confirm_btn.click if (confirm_btn.visible?(timeout: 1000) rescue false)
        end
        page.wait_for_timeout(3000)
        published = true
        break
      end

      if published
        log("[#{self.class.name.split('::').last.sub('Service', '')}] ✅ 公開完了")
      else
        log("[#{self.class.name.split('::').last.sub('Service', '')}] ⚠️ 公開ボタンが見つかりません（既に公開済みの可能性）")
      end
    end

    def log(msg)
      @log_callback&.call(msg.to_s)
    end

    def extract_title(ef, content, max_len = 80)
      raw = ef['title'].presence ||
            ef['name'].presence ||
            content.split("\n").first.to_s.gsub(/\A[#【\s「『]+/, '').gsub(/[】』」\s]+\z/, '')
      raw.to_s[0, max_len].presence || 'イベント'
    end

    def pad_time(t)
      return '10:00' if t.blank?
      t.to_s.sub(/\A(\d):/, '0\1:')
    end

    def default_date_plus(days)
      (Date.today + days).strftime('%Y-%m-%d')
    end

    def normalize_date(d)
      d.to_s.gsub('/', '-')
    end

    # ===== 2Captcha reCAPTCHA解決 =====
    def solve_recaptcha(page, page_url, sitekey: nil)
      captcha_key = ENV['API2CAPTCHA_KEY']
      raise "API2CAPTCHA_KEY が未設定" if captcha_key.blank?

      # sitekeyを自動検出
      sitekey ||= page.evaluate(<<~'JS') rescue nil
        (() => {
          const el = document.querySelector('.g-recaptcha[data-sitekey]');
          if (el) return el.getAttribute('data-sitekey');
          const iframe = document.querySelector('iframe[src*="recaptcha"]');
          if (iframe) {
            const m = iframe.src.match(/[?&]k=([^&]+)/);
            if (m) return m[1];
          }
          return null;
        })()
      JS
      raise "reCAPTCHA sitekeyが検出できません" unless sitekey

      service_name = self.class.name.split('::').last.sub('Service', '')
      log("[#{service_name}] reCAPTCHA解決中（2captcha）... sitekey=#{sitekey[0, 20]}")

      # 2captchaに送信
      uri = URI('http://2captcha.com/in.php')
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(
        key: captcha_key, method: 'userrecaptcha',
        googlekey: sitekey, pageurl: page_url, json: '1',
      )
      res = Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }
      in_json = JSON.parse(res.body)
      raise "2captcha投稿失敗: #{in_json.to_json}" unless in_json['status'] == 1

      request_id = in_json['request']
      sleep 20

      # 結果をポーリング（最大2分）
      24.times do
        res_uri = URI("http://2captcha.com/res.php?key=#{captcha_key}&action=get&id=#{request_id}&json=1")
        res_json = JSON.parse(Net::HTTP.get_response(res_uri).body)
        if res_json['status'] == 1
          log("[#{service_name}] ✅ reCAPTCHA解決完了")
          return res_json['request']
        end
        raise "2captchaエラー: #{res_json.to_json}" if res_json['request'] != 'CAPCHA_NOT_READY'
        sleep 5
      end
      raise "2captchaタイムアウト（2分）"
    end

    # reCAPTCHAトークンをページに注入
    def inject_recaptcha_token(page, token)
      page.evaluate(<<~JS, arg: token)
        (token) => {
          let el = document.querySelector('#g-recaptcha-response');
          if (!el) {
            el = document.createElement('textarea');
            el.id = 'g-recaptcha-response';
            el.name = 'g-recaptcha-response';
            el.style.display = 'none';
            document.body.appendChild(el);
          }
          el.value = token;
          el.innerText = token;
          if (typeof grecaptcha !== 'undefined') {
            try { grecaptcha.enterprise?.execute?.(); } catch(e) {}
          }
        }
      JS
    end
  end
end
