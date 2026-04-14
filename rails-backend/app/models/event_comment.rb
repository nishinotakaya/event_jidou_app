class EventComment < ApplicationRecord
  belongs_to :user, optional: true
  validates :item_id, presence: true
  validates :body, presence: true

  scope :for_item, ->(item_id) { where(item_id: item_id).order(created_at: :asc) }

  def as_json_safe
    {
      id: id,
      itemId: item_id,
      userId: user_id,
      userName: user_name || user&.name || '匿名',
      body: body,
      createdAt: created_at&.iso8601,
    }
  end
end
