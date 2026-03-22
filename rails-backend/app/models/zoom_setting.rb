class ZoomSetting < ApplicationRecord
  validates :zoom_url, presence: true
  validates :label, presence: true
end
