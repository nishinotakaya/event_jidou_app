class XPost < ApplicationRecord
  STATUSES = %w[pending posted failed cancelled].freeze
  SOURCES  = %w[manual ai_generated from_event].freeze
  MAX_LENGTH = 280

  belongs_to :user

  validates :content,      presence: true, length: { maximum: MAX_LENGTH }
  validates :scheduled_at, presence: true
  validates :status,       inclusion: { in: STATUSES }
  validates :source,       inclusion: { in: SOURCES }

  scope :pending,   -> { where(status: "pending") }
  scope :posted,    -> { where(status: "posted") }
  scope :failed,    -> { where(status: "failed") }
  scope :due,       ->(now = Time.current) { pending.where("scheduled_at <= ?", now) }
  scope :for_range, ->(from, to) { where(scheduled_at: from..to) }

  # X の日次上限に自らぶつからないための、直近24時間（ローリング）の投稿数。
  def self.posted_in_last_24h(user_id, now = Time.current)
    where(user_id: user_id).posted.where("posted_at >= ?", now - 24.hours).count
  end

  # 再送待ち（＝上限等で先送りされた pending。error_message に理由が入っている）
  def retry_waiting?
    status == "pending" && error_message.present?
  end

  def post_now!
    update!(scheduled_at: Time.current) if scheduled_at > Time.current
  end

  def mark_posted!(tweet_id:, tweet_url:)
    update!(status: "posted", posted_at: Time.current, tweet_id: tweet_id, tweet_url: tweet_url, error_message: nil)
  end

  def mark_failed!(error_message)
    update!(status: "failed", error_message: error_message.to_s[0, 1000])
  end

  # X の1日投稿上限（code 344）など一時的な理由で送れなかったとき、
  # 失敗扱いにせず pending のまま送信予定を先送りして後で自動リトライさせる。
  def reschedule!(run_at, reason: nil)
    update!(status: "pending", scheduled_at: run_at, error_message: reason.to_s[0, 1000].presence)
  end
end
