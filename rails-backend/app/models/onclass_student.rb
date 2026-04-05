class OnclassStudent < ApplicationRecord
  validates :name, presence: true

  scope :frontend_course, -> { where(course: 'フロントエンジニアコース') }
end
