# sidekiq-cron から毎分呼ばれるバッチ。
# ActiveJob だと sidekiq-cron が定数を解決できず文字列クラスとして push し、
# ワーカーが Sidekiq worker 扱いで instance.jid= を呼んで NoMethodError になる。
# そのためネイティブ Sidekiq::Job として定義する。
class XPostScheduledJob
  include Sidekiq::Job

  # scheduled_at <= 現在時刻 の pending な XPost を順に投稿。
  # 1 回の起動で最大 N 件まで処理（バースト防止）。投稿ロジックは X::Publisher に集約。
  MAX_PER_RUN = 10

  def perform
    due = XPost.due.order(:scheduled_at).limit(MAX_PER_RUN)
    return if due.empty?

    due.each do |post|
      result = X::Publisher.new(post).call
      Rails.logger.error("[XPostScheduledJob] post=#{post.id} 投稿失敗: #{result.error}") unless result.ok?
    end
  end
end
