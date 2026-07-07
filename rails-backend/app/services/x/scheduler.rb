module X
  # 生成されたツイート群を、指定期間（開始日〜N日）と時間帯ルールに従って
  # scheduled_at に分配する。
  class Scheduler
    # time_slots: 投稿時間帯ラベルの配列。"morning" / "noon" / "evening" / "night"
    TIME_SLOTS = {
      'morning' => [7, 8, 9],    # 7-9 時から 1 つ選ぶ
      'noon'    => [12, 13],     # 12-13 時
      'evening' => [18, 19, 20], # 18-20 時
      'night'   => [21, 22, 23], # 21-23 時
    }.freeze

    # @param tweets [Array<String>] 本文配列
    # @param start_date [Date]
    # @param days [Integer]
    # @param per_day [Integer] 1日あたりの投稿数（time_slots の数まで）
    # @param time_slots [Array<String>] ["morning", "evening"] 等
    # @return [Array<{ content: String, scheduled_at: Time }>]
    def self.distribute(tweets:, start_date:, days:, per_day:, time_slots:)
      slots = time_slots.select { |s| TIME_SLOTS.key?(s) }
      slots = TIME_SLOTS.keys if slots.empty?
      per_day = [per_day, slots.size].min
      per_day = 1 if per_day < 1

      total_slots = days * per_day
      tweets = tweets.first(total_slots)
      result = []

      tweets.each_with_index do |text, idx|
        day_offset = idx / per_day
        slot_index = idx % per_day
        slot_label = slots[slot_index] || slots.first
        hour       = TIME_SLOTS[slot_label].sample
        minute     = [0, 15, 30, 45].sample
        scheduled  = start_date.to_date.+(day_offset).to_time.change(hour: hour, min: minute)
        result << { content: text, scheduled_at: scheduled }
      end
      result
    end
  end
end
