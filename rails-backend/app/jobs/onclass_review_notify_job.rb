require 'playwright'

class OnclassReviewNotifyJob < ApplicationJob
  queue_as :default

  BASE_URL = 'https://manager.the-online-class.com'.freeze

  # GitHubレビュー完了後にオンクラスのコミュニティに通知を送信
  def perform(review_id)
    review = GithubReview.find(review_id)
    return unless review.status == 'posted'

    # 投稿先チャンネルを推定（元のメンションのチャンネル or デフォルト）
    channel = detect_channel(review)
    message = build_message(review)

    logger.info "[OnClass通知] チャンネル「#{channel}」にレビュー完了通知を送信中..."

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: true)
      page = browser.new_page

      begin
        ensure_login(page)
        navigate_to_community(page)
        select_channel(page, channel)
        send_message(page, message)
        logger.info "[OnClass通知] ✅ 送信完了"
      ensure
        browser.close
      end
    end
  rescue => e
    logger.error "[OnClass通知] ❌ #{e.message}"
  end

  private

  def build_message(review)
    pr_label = review.pr_number ? "PR ##{review.pr_number}" : review.github_type
    comment_url = review.github_comment_url

    msg = "Gitレビュー完了しました！ご確認のほどお願いします。\n\n"
    msg += "📝 #{review.repo_full_name} #{pr_label}\n"
    msg += "🔗 #{review.github_url}\n"
    msg += "💬 レビューコメント: #{comment_url}\n" if comment_url.present?
    msg
  end

  # 元のメンションのチャンネルを推定
  def detect_channel(review)
    repo = review.repo_full_name.to_s.downcase
    if repo.include?('todo') && repo.include?('b')
      'TodoB - 報告'
    elsif repo.include?('todo') && repo.include?('a')
      'TodoA - 報告'
    elsif repo.include?('portfolio') || repo.include?('ポートフォリオ')
      'クローンチーム'
    elsif repo.include?('pdca')
      'PDCAアプリ開発'
    else
      '全体チャンネル'
    end
  end

  def ensure_login(page)
    creds = ServiceConnection.credentials_for('onclass')
    email = creds[:email].presence || 'takaya314boxing@gmail.com'
    password = creds[:password].presence || 'takaya314'

    page.goto("#{BASE_URL}/sign_in", timeout: 30_000, waitUntil: 'load')
    page.wait_for_timeout(3000)
    return if !page.url.include?('sign_in')

    page.fill('input[name="email"]', email)
    page.fill('input[name="password"]', password)
    page.locator('button:has-text("ログインする")').click
    page.wait_for_timeout(5000)
    raise 'オンクラスログイン失敗' if page.url.include?('sign_in')
  end

  def navigate_to_community(page)
    page.goto("#{BASE_URL}/community", timeout: 30_000, waitUntil: 'load')
    page.wait_for_timeout(5000)
  end

  def select_channel(page, channel_name)
    escaped = channel_name.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")
    page.evaluate(<<~JS)
      (() => {
        const name = '#{escaped}';
        const items = [...document.querySelectorAll('.v-list-item')];
        const target = items.find(el => {
          const title = el.querySelector('.v-list-item-title');
          return (title && title.textContent.trim() === name) || el.textContent.trim() === name;
        });
        if (target) {
          target.scrollIntoView({ block: 'center', behavior: 'instant' });
          target.click();
        }
      })()
    JS
    page.wait_for_timeout(3000)
  end

  def send_message(page, message)
    textarea = page.locator('textarea.v-field__input').first
    textarea.click
    page.wait_for_timeout(500)
    textarea.type(message)
    page.wait_for_timeout(1000)

    send_icon = page.locator('i.mdi-arrow-up-box, [class*="_send_icon_"]').first
    send_icon.click(force: true)
    page.wait_for_timeout(3000)
  end
end
