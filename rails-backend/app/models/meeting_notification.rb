# 毎週の定例ミーティングを、指定曜日・時刻にオンクラスのコミュニティチャンネルへ
# 自動通知するための設定。1 チーム（＝1 チャンネル）につき 1 レコード。
class MeetingNotification < ApplicationRecord
  ZONE = ActiveSupport::TimeZone["Asia/Tokyo"]
  WEEKDAY_LABELS = %w[日 月 火 水 木 金 土].freeze
  TIME_FORMAT = /\A\d{1,2}:\d{2}\z/

  validates :name, :onclass_channel, :zoom_url, presence: true
  validates :weekday, inclusion: { in: 0..6 }
  validates :start_time, :notify_time, format: { with: TIME_FORMAT, message: "は HH:MM 形式で入力してください" }

  scope :enabled, -> { where(enabled: true) }

  # 現在時刻（JST）が「送信すべき瞬間」を過ぎていて、今日まだ送っていなければ true。
  # cron は数分間隔で回るため、notify_time を過ぎた最初の実行で 1 回だけ送る。
  def due?(now = ZONE.now)
    return false unless enabled?
    return false unless now.wday == weekday
    return false if last_sent_on == now.to_date

    now >= notify_at(now.to_date)
  end

  # 指定日の通知送信時刻（JST の TimeWithZone）
  def notify_at(date = ZONE.today)
    hour, min = notify_time.to_s.split(":").map(&:to_i)
    ZONE.local(date.year, date.month, date.day, hour.to_i, min.to_i)
  end

  # 「2026年7月5日（日）」形式
  def meeting_date_label(date = ZONE.today)
    "#{date.year}年#{date.month}月#{date.day}日（#{WEEKDAY_LABELS[date.wday]}）"
  end

  # 「22:00〜22:30」形式（end 未設定なら開始のみ）
  def meeting_time_label
    end_time.present? ? "#{start_time}〜#{end_time}" : start_time.to_s
  end

  # 11 桁の数字なら「889 9861 5545」形式に整形。それ以外は原文のまま。
  def formatted_meeting_id
    digits = meeting_id.to_s.gsub(/\D/, "")
    return meeting_id.to_s unless digits.length == 11

    "#{digits[0, 3]} #{digits[3, 4]} #{digits[7, 4]}"
  end
end
