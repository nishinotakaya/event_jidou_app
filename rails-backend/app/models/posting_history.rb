class PostingHistory < ApplicationRecord
  belongs_to :item, primary_key: :id, foreign_key: :item_id, optional: true

  validates :item_id, presence: true
  validates :site_name, presence: true

  scope :for_item, ->(item_id) { where(item_id: item_id).order(posted_at: :desc) }
  # SQLite対応: サイトごとに最新の投稿履歴を取得
  def self.latest_per_site(item_id)
    where(item_id: item_id).order(posted_at: :desc).group_by(&:site_name).map { |_, v| v.first }
  end

  # サイト表示名マッピング
  SITE_LABELS = {
    'kokuchpro'      => 'こくチーズ',
    'connpass'       => 'connpass',
    'peatix'         => 'Peatix',
    'techplay'       => 'TechPlay',
    'tunagate'       => 'つなゲート',
    'doorkeeper'     => 'Doorkeeper',
    'seminars'       => 'セミナーズ',
    'street_academy' => 'ストアカ',
    'eventregist'    => 'EventRegist',
    'passmarket'     => 'PassMarket',
    'luma'           => 'Luma',
    'seminar_biz'    => 'セミナーBiZ',
    'jimoty'         => 'ジモティー',
    'twitter'        => 'X',
    'instagram'      => 'Instagram',
    'gmail'          => 'Gmail',
    'onclass'        => 'オンクラス',
  }.freeze

  def as_json_safe
    {
      id: id,
      itemId: item_id,
      siteName: site_name,
      siteLabel: SITE_LABELS[site_name] || site_name,
      status: status,
      eventUrl: event_url,
      published: published,
      errorMessage: error_message,
      postedAt: posted_at&.iso8601,
      registrations: registrations,
      registrationsCheckedAt: registrations_checked_at&.iso8601,
    }
  end
end
