redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url, size: 3 }
  config.concurrency = ENV.fetch('SIDEKIQ_CONCURRENCY', 2).to_i
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url, size: 2 }
end
