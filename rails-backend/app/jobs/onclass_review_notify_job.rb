require 'playwright'

# GitHub レビュー完了後に、オンクラスのコミュニティチャンネルへ
# 「レビュー完了通知」を Playwright 経由で自動投稿する ActiveJob。
#
# 呼び出し元:
#   Api::GithubReviewsController#post_to_github
#     → OnclassReviewNotifyJob.perform_later(review.id)
#
# 前提:
#   - GithubReview が status='posted' に更新済みであること
#   - オンクラスの認証情報が ServiceConnection もしくは ENV に設定済みであること
#
# 注意:
#   - 例外は最終的に rescue で握り潰している（= ActiveJob の自動リトライは発火しない）。
#     通知失敗でユーザー作業を止めたくないため意図的に silent にしている。
class OnclassReviewNotifyJob < ApplicationJob
  queue_as :default

  BASE_URL      = 'https://manager.the-online-class.com'.freeze
  LOGIN_PATH    = '/sign_in'.freeze
  COMMUNITY_PATH = '/community'.freeze

  # Playwright 系の各ステップで共通で使う待機時間（ミリ秒）
  GOTO_TIMEOUT_MS       = 30_000
  POST_LOGIN_WAIT_MS    = 5_000
  POST_GOTO_WAIT_MS     = 5_000
  SHORT_WAIT_MS         = 3_000
  INPUT_WAIT_MS         = 500
  TYPE_WAIT_MS          = 1_000

  # ログイン情報が ServiceConnection / ENV いずれにも無かった場合の最終フォールバック。
  # 本番環境では ServiceConnection を設定してここに依存しないこと。
  FALLBACK_EMAIL    = 'takaya314boxing@gmail.com'.freeze
  FALLBACK_PASSWORD = 'takaya314'.freeze

  # 投稿先チャンネルの振り分けルール。
  # 先頭から順に評価し、最初にマッチした :channel を採用する。
  # NOTE: マッチ条件は歴史的経緯でゆるい include? ベース。
  #       意図せぬ誤振り分けを避けたい場合はここを厳密化する。
  CHANNEL_ROUTES = [
    { match: ->(r) { r.include?('todo') && r.include?('b') },   channel: 'TodoB - 報告' },
    { match: ->(r) { r.include?('todo') && r.include?('a') },   channel: 'TodoA - 報告' },
    { match: ->(r) { r.include?('portfolio') || r.include?('ポートフォリオ') }, channel: 'クローンチーム' },
    { match: ->(r) { r.include?('pdca') },                       channel: 'PDCAアプリ開発' },
  ].freeze
  DEFAULT_CHANNEL = '全体チャンネル'.freeze

  def perform(review_id)
    review = GithubReview.find(review_id)
    # 'posted'（GitHub へのコメント投稿完了済み）以外は通知不要
    return unless review.status == 'posted'

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
        logger.info '[OnClass通知] ✅ 送信完了'
      ensure
        # 例外時でも必ずブラウザを閉じてリソースリークを防ぐ
        browser.close
      end
    end
  rescue => e
    # 通知失敗はユーザー操作を止めない（ログのみ。リトライしない）
    logger.error "[OnClass通知] ❌ #{e.message}"
  end

  private

  # ------------------------------------------------------------------
  # メッセージ組み立て
  # ------------------------------------------------------------------

  # コミュニティに投稿する本文を組み立てる
  def build_message(review)
    pr_label    = review.pr_number ? "PR ##{review.pr_number}" : review.github_type
    comment_url = review.github_comment_url

    lines = []
    lines << 'Gitレビュー完了しました！ご確認のほどお願いします。'
    lines << ''
    lines << "📝 #{review.repo_full_name} #{pr_label}"
    lines << "🔗 #{review.github_url}"
    lines << "💬 レビューコメント: #{comment_url}" if comment_url.present?
    lines.join("\n") + "\n"
  end

  # リポジトリ名から投稿先チャンネルを推定する。
  # CHANNEL_ROUTES の先頭から評価し、最初にマッチしたチャンネルを返す。
  def detect_channel(review)
    repo = review.repo_full_name.to_s.downcase
    route = CHANNEL_ROUTES.find { |r| r[:match].call(repo) }
    route ? route[:channel] : DEFAULT_CHANNEL
  end

  # ------------------------------------------------------------------
  # Playwright ステップ（呼び出し順に並べる）
  # ------------------------------------------------------------------

  # オンクラスにログイン。既にログイン済みならスキップ。
  def ensure_login(page)
    creds    = ServiceConnection.credentials_for('onclass')
    email    = creds[:email].presence    || FALLBACK_EMAIL
    password = creds[:password].presence || FALLBACK_PASSWORD

    page.goto("#{BASE_URL}#{LOGIN_PATH}", timeout: GOTO_TIMEOUT_MS, waitUntil: 'load')
    page.wait_for_timeout(SHORT_WAIT_MS)

    # URLに 'sign_in' が残っていなければ既にログイン済み
    return unless page.url.include?('sign_in')

    page.fill('input[name="email"]', email)
    page.fill('input[name="password"]', password)
    page.locator('button:has-text("ログインする")').click
    page.wait_for_timeout(POST_LOGIN_WAIT_MS)

    raise 'オンクラスログイン失敗' if page.url.include?('sign_in')
  end

  # コミュニティビューに遷移
  def navigate_to_community(page)
    page.goto("#{BASE_URL}#{COMMUNITY_PATH}", timeout: GOTO_TIMEOUT_MS, waitUntil: 'load')
    page.wait_for_timeout(POST_GOTO_WAIT_MS)
  end

  # 指定チャンネルをクリックして選択状態にする。
  # Vuetify の v-list-item を DOM から直接探してクリックする。
  def select_channel(page, channel_name)
    # チャンネル名を JS 文字列リテラルに安全に埋め込む。
    # 以前は gsub で手動エスケープしていたが、`\'` が gsub の後方参照扱いとなり
    # アポストロフィを含む名前で文字列が壊れる不具合があったため to_json に統一。
    name_literal = channel_name.to_json

    page.evaluate(<<~JS)
      (() => {
        const name = #{name_literal};
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
    page.wait_for_timeout(SHORT_WAIT_MS)
  end

  # textarea にメッセージを入力し、送信アイコンをクリックする
  def send_message(page, message)
    textarea = page.locator('textarea.v-field__input').first
    textarea.click
    page.wait_for_timeout(INPUT_WAIT_MS)
    textarea.type(message)
    page.wait_for_timeout(TYPE_WAIT_MS)

    # 送信ボタン: mdi-arrow-up-box アイコン、または _send_icon_ を含むクラス。
    # オーバーレイ等で遮られることがあるため force: true でクリック。
    send_icon = page.locator('i.mdi-arrow-up-box, [class*="_send_icon_"]').first
    send_icon.click(force: true)
    page.wait_for_timeout(SHORT_WAIT_MS)
  end
end
