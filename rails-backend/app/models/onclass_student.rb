class OnclassStudent < ApplicationRecord
  validates :name, presence: true

  scope :frontend_course, -> { where(course: 'フロントエンジニアコース') }
  scope :active, -> { where('expires_at IS NULL OR expires_at >= ?', Date.today) }
  scope :active_frontend, -> { frontend_course.where('expires_at IS NULL OR expires_at >= ?', Date.today) }
end
