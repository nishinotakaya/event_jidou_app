redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url, size: 3 }
  config.concurrency = ENV.fetch("SIDEKIQ_CONCURRENCY", 2).to_i

  # XPost のスケジュール投稿: 毎分 due な pending を投稿
  config.on(:startup) do
    schedule = {
      "x_post_scheduled" => {
        "cron"  => "*/5 * * * *",
        "class" => "XPostScheduledJob"
      },
      # 定例ミーティング通知: 5分間隔で判定（曜日・送信時刻の判定は due?(JST) 側で行う。
      # 該当設定が無ければオンクラスへのログインもせず即 return する）
      "meeting_notify" => {
        "cron"  => "*/5 * * * *",
        "class" => "MeetingNotifyJob"
      }
    }
    Sidekiq::Cron::Job.load_from_hash(schedule) if defined?(Sidekiq::Cron::Job)
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url, size: 2 }
end
