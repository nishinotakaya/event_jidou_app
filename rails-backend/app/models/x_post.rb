class XPost < ApplicationRecord
  STATUSES = %w[pending posted failed cancelled].freeze
  SOURCES  = %w[manual ai_generated from_event].freeze
  MAX_LENGTH = 280

  belongs_to :user

  validates :content,      presence: true, length: { maximum: MAX_LENGTH }
  validates :scheduled_at, presence: true
  validates :status,       inclusion: { in: STATUSES }
  validates :source,       inclusion: { in: SOURCES }

  scope :pending,   -> { where(status: 'pending') }
  scope :posted,    -> { where(status: 'posted') }
  scope :failed,    -> { where(status: 'failed') }
  scope :due,       ->(now = Time.current) { pending.where('scheduled_at <= ?', now) }
  scope :for_range, ->(from, to) { where(scheduled_at: from..to) }

  def post_now!
    update!(scheduled_at: Time.current) if scheduled_at > Time.current
  end

  def mark_posted!(tweet_id:, tweet_url:)
    update!(status: 'posted', posted_at: Time.current, tweet_id: tweet_id, tweet_url: tweet_url, error_message: nil)
  end

  def mark_failed!(error_message)
    update!(status: 'failed', error_message: error_message.to_s[0, 1000])
  end
end
