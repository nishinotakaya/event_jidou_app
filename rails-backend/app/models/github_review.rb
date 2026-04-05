class GithubReview < ApplicationRecord
  belongs_to :user, optional: true

  STATUSES = %w[pending reviewed approved posted].freeze
  TYPES = %w[pr issue repo commit].freeze

  validates :github_url, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :reviewed, -> { where(status: 'reviewed') }
  scope :not_posted, -> { where.not(status: 'posted') }

  def images_list
    return [] if images.blank?
    JSON.parse(images)
  rescue JSON::ParserError
    []
  end

  def images_list=(arr)
    self.images = arr.to_json
  end
end
