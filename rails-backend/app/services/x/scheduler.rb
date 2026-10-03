module X
  # 生成されたツイート群を、指定期間（開始日〜N日）と時間帯ルールに従って
  # scheduled_at に分配する。
  class Scheduler
    # time_slots: 投稿時間帯ラベルの配列。"morning" / "noon" / "evening" / "night"
    TIME_SLOTS = {
      "morning" => [ 7, 8, 9 ],    # 7-9 時から 1 つ選ぶ
      "noon"    => [ 12, 13 ],     # 12-13 時
      "evening" => [ 18, 19, 20 ], # 18-20 時
      "night"   => [ 21, 22, 23 ] # 21-23 時
    }.freeze

    # 時間帯は日本時間（JST）で解釈する。アプリの Time.zone は UTC 既定のため、
    # ここで明示的に Asia/Tokyo を使わないと "morning 7時" が UTC 7時（JST 16時）にずれる。
    ZONE = ActiveSupport::TimeZone["Asia/Tokyo"]

    # 生成直後に cron（毎分の XPostScheduledJob）へ即拾われないための最小リード。
    MIN_LEAD = 5.minutes

    # @param tweets [Array<String>] 本文配列
    # @param start_date [Date]
    # @param days [Integer]
    # @param per_day [Integer] 1日あたりの投稿数（time_slots の数まで）
    # @param time_slots [Array<String>] ["morning", "evening"] 等
    # @return [Array<{ content: String, scheduled_at: Time }>]
    def self.distribute(tweets:, start_date:, days:, per_day:, time_slots:)
      slots = time_slots.select { |s| TIME_SLOTS.key?(s) }
      slots = TIME_SLOTS.keys if slots.empty?
      # 1日の中で時刻順（morning→noon→evening→night）に並べる
      slots   = slots.sort_by { |label| TIME_SLOTS[label].first }
      per_day = per_day.to_i.clamp(1, slots.size)

      earliest = ZONE.now + MIN_LEAD
      start    = (ZONE.parse(start_date.to_s)&.to_date || ZONE.today)

      result      = []
      queue       = tweets.dup
      day_offset  = 0
      # 過去スロットのスキップで日が足りなくなる場合に備えた安全上限
      max_offset  = days + 60

      while queue.any? && day_offset <= max_offset
        slots.first(per_day).each do |label|
          break if queue.empty?
          hour      = TIME_SLOTS[label].sample
          minute    = [ 0, 15, 30, 45 ].sample
          scheduled = ZONE.local(start.year, start.month, start.day, hour, minute) + day_offset.days
          next if scheduled <= earliest # 過去・直近はスキップして未来のスロットへ

          result << { content: queue.shift, scheduled_at: scheduled }
        end
        day_offset += 1
      end
      result
    end
  end
end
