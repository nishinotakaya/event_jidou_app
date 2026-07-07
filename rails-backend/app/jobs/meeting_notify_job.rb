# 定例ミーティング通知の自動投稿バッチ。
# sidekiq-cron から数分間隔で呼ばれ、送信時刻を過ぎた設定を 1 回だけ投稿する。
#
# XPostScheduledJob と同様、sidekiq-cron が定数を解決できるよう
# ActiveJob ではなくネイティブ Sidekiq::Job として定義する。
class MeetingNotifyJob
  include Sidekiq::Job

  def perform
    configs = MeetingNotification.enabled.select(&:due?)
    return if configs.empty?

    # チャンネル解決のため 1 度だけログインしてチャンネル一覧をキャッシュする
    client = OnclassApiClient.from_service_connection
    client.sign_in!
    channels = client.channels

    configs.each do |config|
      self.class.deliver(config, client: client, channels: channels)
    rescue => e
      Rails.logger.error("[MeetingNotifyJob] #{config.name} 送信失敗: #{e.message}")
    end
  end

  # 1 件の通知を実際に投稿する。cron（due 判定済み）とテスト送信の両方から使う。
  # @return [String] 投稿した本文
  def self.deliver(config, client: nil, channels: nil, date: nil)
    client ||= OnclassApiClient.from_service_connection.tap(&:sign_in!)
    channels ||= client.channels

    channel = find_channel(channels, config.onclass_channel)
    raise "チャンネル「#{config.onclass_channel}」が見つかりません" unless channel

    text = MeetingNotificationComposer.new(config, date: date).call
    client.create_chat(channel_id: channel["id"], text: text)
    config.update!(last_sent_on: (date || MeetingNotification::ZONE.today))
    Rails.logger.info("[MeetingNotifyJob] ✅ #{config.name} → #{config.onclass_channel} 送信完了")
    text
  end

  # 名前の空白揺れを無視してチャンネルを引く
  def self.find_channel(channels, name)
    wanted = name.to_s.gsub(/[[:space:]]+/, "")
    channels.find { |c| c["name"].to_s.gsub(/[[:space:]]+/, "") == wanted } ||
      channels.find do |c|
        normalized = c["name"].to_s.gsub(/[[:space:]]+/, "")
        normalized.include?(wanted) || wanted.include?(normalized)
      end
  end
end
