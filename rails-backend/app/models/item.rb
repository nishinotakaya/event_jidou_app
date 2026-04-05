class Item < ApplicationRecord
  self.primary_key = 'id'

  belongs_to :user, optional: true

  validates :name, presence: true
  validates :item_type, inclusion: { in: %w[event student] }
  validate :no_duplicate_event_datetime, on: :create

  before_create :set_custom_id

  private

  # 同じ開催日+開始時間のイベントが既にある場合はエラー
  def no_duplicate_event_datetime
    return unless item_type == 'event'
    return if event_date.blank?

    scope = Item.where(item_type: 'event', event_date: event_date)
    scope = scope.where(user_id: user_id) if user_id.present?

    if event_time.present?
      existing = scope.where(event_time: event_time).where.not(id: id)
      if existing.exists?
        errors.add(:base, "同じ開催日時（#{event_date} #{event_time}）のイベントが既に存在します")
      end
    else
      existing = scope.where(event_time: [nil, '']).where.not(id: id)
      if existing.exists?
        errors.add(:base, "同じ開催日（#{event_date}）のイベントが既に存在します")
      end
    end
  end

  def set_custom_id
    prefix = item_type == 'event' ? 'event_' : 'student_'
    nums = Item.where(item_type: item_type)
                .map { |i| i.id.to_s.sub(prefix, '').to_i }
                .select { |n| n > 0 }
    self.id = "#{prefix}#{((nums.max || 0) + 1).to_s.rjust(3, '0')}"
  end
end
