# GitHub レビュー完了後に、オンクラスのコミュニティチャンネルへ
# 「レビュー完了通知」を自動投稿する ActiveJob（API 直叩き・Playwright 不要）。
#
# 呼び出し元:
#   Api::GithubReviewsController#post_to_github
#     → OnclassReviewNotifyJob.perform_later(review.id)
#
# 前提:
#   - GithubReview が status='posted' に更新済みであること
#   - オンクラスの認証情報が ServiceConnection に設定済みであること
#
# 注意:
#   - 例外は最終的に rescue で握り潰している（= ActiveJob の自動リトライは発火しない）。
#     通知失敗でユーザー作業を止めたくないため意図的に silent にしている。
class OnclassReviewNotifyJob < ApplicationJob
  queue_as :default

  # 投稿先チャンネルの振り分けルール。
  # 先頭から順に評価し、最初にマッチした :channel を採用する。
  # NOTE: マッチ条件は歴史的経緯でゆるい include? ベース。
  #       意図せぬ誤振り分けを避けたい場合はここを厳密化する。
  CHANNEL_ROUTES = [
    { match: ->(r) { r.include?("todo") && r.include?("b") },   channel: "TodoB - 報告" },
    { match: ->(r) { r.include?("todo") && r.include?("a") },   channel: "TodoA - 報告" },
    { match: ->(r) { r.include?("portfolio") || r.include?("ポートフォリオ") }, channel: "クローンチーム" },
    { match: ->(r) { r.include?("pdca") },                       channel: "PDCAアプリ開発" }
  ].freeze
  DEFAULT_CHANNEL = "全体チャンネル".freeze

  def perform(review_id)
    review = GithubReview.find(review_id)
    # 'posted'（GitHub へのコメント投稿完了済み）以外は通知不要
    return unless review.status == "posted"

    channel_name = detect_channel(review)
    message = build_message(review)

    logger.info "[OnClass通知] チャンネル「#{channel_name}」にレビュー完了通知を送信中..."

    client = OnclassApiClient.from_service_connection(logger: logger)
    client.sign_in!

    channel = find_channel(client, channel_name)
    client.create_chat(channel_id: channel["id"], text: message)
    logger.info "[OnClass通知] ✅ 送信完了"
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
    lines << "Gitレビュー完了しました！ご確認のほどお願いします。"
    lines << ""
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

  # チャンネル名から API のチャンネルを引く（名前の空白揺れは無視して比較）
  def find_channel(client, channel_name)
    wanted = channel_name.to_s.gsub(/[[:space:]]+/, "")
    channel = client.channels.find { |c| c["name"].to_s.gsub(/[[:space:]]+/, "") == wanted }
    raise "チャンネル「#{channel_name}」が見つかりません" unless channel

    channel
  end
end
