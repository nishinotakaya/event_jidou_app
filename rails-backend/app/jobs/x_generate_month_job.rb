class XGenerateMonthJob < ApplicationJob
  queue_as :default

  # 1 ヶ月分（最大 90 ツイート）の AI 生成を Sidekiq に投げて Heroku 30s ルーター制限を回避。
  # 進捗は ActionCable("x_generate_<job_id>") にブロードキャストし、フロントが購読する。
  def perform(job_id, user_id, params)
    user = User.find_by(id: user_id)
    return broadcast(job_id, type: 'error', message: 'ユーザーが見つかりません') unless user

    days       = (params['days'] || 30).to_i
    per_day    = (params['per_day'] || 2).to_i
    start_date = parse_date(params['start_date']) || Date.tomorrow
    slots      = Array(params['time_slots']).presence || %w[morning evening]
    extra      = params['extra_theme']
    count      = days * per_day

    broadcast(job_id, type: 'log', message: "🤖 OpenAI で #{count} ツイートを生成中...")
    tweets = X::AiGenerator.generate(count: count, extra_theme: extra, api_key: params['apiKey'])
    broadcast(job_id, type: 'log', message: "✅ 生成完了 (#{tweets.size} 件)")

    planned = X::Scheduler.distribute(
      tweets: tweets, start_date: start_date, days: days, per_day: per_day, time_slots: slots,
    )

    if params['dry_run'].to_s == 'true'
      broadcast(job_id, type: 'done', planned: planned.map { |p| { content: p[:content], scheduled_at: p[:scheduled_at].iso8601 } })
      return
    end

    created = planned.map do |row|
      user.x_posts.create!(content: row[:content], scheduled_at: row[:scheduled_at], source: 'ai_generated')
    end

    # === window 内のイベントに対して告知シリーズ（1週間前 / 3日前 / 当日朝 / 10分前）を追加 ===
    window_end = start_date + days.days
    events_in_window = user.items.where(item_type: 'event')
                                 .where.not(event_date: [nil, ''])
                                 .where('event_date BETWEEN ? AND ?', start_date.to_s, window_end.to_s)
    event_announcements = []
    events_in_window.find_each do |item|
      signup_url = X::EventAnnouncer.pick_signup_url(item.id)
      if signup_url.blank?
        broadcast(job_id, type: 'log', message: "↳ #{item.name}: 申込 URL 未取得のため告知シリーズはスキップ")
        next
      end
      broadcast(job_id, type: 'log', message: "🎉 #{item.name} (#{item.event_date}) の告知シリーズ生成中...")
      added = X::EventAnnouncer.generate_and_save(
        user: user, item_id: item.id, title: item.name,
        event_date: item.event_date, event_time: item.event_time, signup_url: signup_url,
      )
      event_announcements.concat(added)
      broadcast(job_id, type: 'log', message: "  → #{added.size} 件追加")
    end

    broadcast(job_id, type: 'done',
              posts: created.map { |p| serialize(p) },
              event_announcements: event_announcements.map { |p| serialize(p) })
  rescue => e
    Rails.logger.error("[XGenerateMonthJob] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    broadcast(job_id, type: 'error', message: "#{e.class}: #{e.message}")
  end

  private

  def broadcast(job_id, payload)
    ActionCable.server.broadcast("x_generate_#{job_id}", payload)
  end

  def parse_date(s) = (Date.parse(s.to_s) rescue nil)

  def serialize(p)
    {
      id: p.id, content: p.content, image_url: p.image_url,
      scheduled_at: p.scheduled_at, status: p.status,
      posted_at: p.posted_at, tweet_url: p.tweet_url,
      error_message: p.error_message, source: p.source, item_id: p.item_id,
    }
  end
end
