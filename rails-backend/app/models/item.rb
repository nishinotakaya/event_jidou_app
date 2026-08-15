class Item < ApplicationRecord
  self.primary_key = 'id'

  belongs_to :user, optional: true

  validates :name, presence: true
  validates :item_type, inclusion: { in: %w[event student] }
  # 同タイトル・同日時の重複は意図的に許容（同じ告知を複数回出すユースケースのため）

  before_create :set_custom_id

  private

  def set_custom_id
    prefix = item_type == 'event' ? 'event_' : 'student_'
    nums = Item.where(item_type: item_type)
                .map { |i| i.id.to_s.sub(prefix, '').to_i }
                .select { |n| n > 0 }
    self.id = "#{prefix}#{((nums.max || 0) + 1).to_s.rjust(3, '0')}"
  end
end
