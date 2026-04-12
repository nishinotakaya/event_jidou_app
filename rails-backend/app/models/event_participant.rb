class EventParticipant < ApplicationRecord
  validates :item_id, presence: true
  validates :site_name, presence: true

  scope :for_item, ->(item_id) { where(item_id: item_id).order(:site_name, :name) }

  def as_json_safe
    { id: id, itemId: item_id, siteName: site_name, name: name, email: email }
  end
end
