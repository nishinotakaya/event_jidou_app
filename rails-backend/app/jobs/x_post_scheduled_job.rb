# sidekiq-cron から毎分呼ばれるバッチ。
# ActiveJob だと sidekiq-cron が定数を解決できず文字列クラスとして push し、
# ワーカーが Sidekiq worker 扱いで instance.jid= を呼んで NoMethodError になる。
# そのためネイティブ Sidekiq::Job として定義する。
class XPostScheduledJob
  include Sidekiq::Job
  # 定期実行なので失敗しても次回で拾える。リトライさせない（DBクエリ上限などで
  # 失敗した際にリトライが積み上がり、上限を食い潰す悪循環を防ぐ）。
  sidekiq_options retry: false

  # scheduled_at <= 現在時刻 の pending な XPost を順に投稿。
  # 1 回の起動で最大 N 件まで処理（バースト防止）。投稿ロジックは X::Publisher に集約。
  MAX_PER_RUN = 10

  # 1 アカウントあたりの「直近24時間の投稿本数」上限。X の日次上限に自らぶつからないための
  # 自主制限。超過分は翌日へ自動先送りする。ENV で調整可能。
  DAILY_LIMIT = ENV.fetch("X_DAILY_POST_LIMIT", 15).to_i

  def perform
    due = XPost.due.order(:scheduled_at).limit(MAX_PER_RUN)
    return if due.empty?

    # 直近24hの投稿数はユーザーごとに1回だけ数え、成功のたびにローカルで加算する
    # （ループ内で毎回 COUNT を投げるとクエリが増えるため）。
    posted_counts = Hash.new { |cache, user_id| cache[user_id] = XPost.posted_in_last_24h(user_id) }

    due.each do |post|
      # 自主上限に達しているユーザーの投稿は、投げずに翌日の同時刻へ先送りする
      # （X の日次上限に当たって失敗扱いになるのを未然に防ぐ）。
      if posted_counts[post.user_id] >= DAILY_LIMIT
        run_at = post.scheduled_at + 1.day
        post.reschedule!(run_at, reason: "1日の投稿上限(#{DAILY_LIMIT}件)に達したため翌日へ先送り")
        Rails.logger.info("[XPostScheduledJob] post=#{post.id} 自主上限で#{run_at}へ先送り")
        next
      end

      result = X::Publisher.new(post).call
      if result.ok?
        posted_counts[post.user_id] += 1
        next
      end

      # X 側の日次上限に当たったら、この回の残りも同じ上限で弾かれるので即打ち切る
      # （当該ポストは Publisher 側で再送予定に先送り済み）。
      if result.rate_limited
        Rails.logger.warn("[XPostScheduledJob] X日次上限のため今回の残りをスキップ")
        break
      end

      Rails.logger.error("[XPostScheduledJob] post=#{post.id} 投稿失敗: #{result.error}")
    end
  rescue ActiveRecord::StatementInvalid => e
    # JawsDB のクエリ上限(max_questions)超過などは一時的。リトライ storm を起こさず静かに退避。
    raise unless e.message.to_s.include?("max_questions")

    Rails.logger.warn("[XPostScheduledJob] DBクエリ上限のため今回はスキップ")
  end
end
