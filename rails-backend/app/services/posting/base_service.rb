module Posting
  class BaseService
    def call(page, content, event_fields = {}, &log_callback)
      @log_callback = log_callback
      execute(page, content, event_fields)
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
  end
end
