# 交流会リサーチで星を付けたイベント（ユーザーごと）。
class ResearchFavorite < ApplicationRecord
  # url はユニークインデックス（user_id と複合）を張っている都合で 512 文字まで。
  # 実在のイベントURLは 100 文字前後なので、超える場合は保存せずエラーを返す。
  URL_MAX_LENGTH = 512

  belongs_to :user

  validates :url, presence: true, length: { maximum: URL_MAX_LENGTH },
                  uniqueness: { scope: :user_id, message: "は既にお気に入りに入っています" }
  validates :title, presence: true
  validates :site, presence: true

  # 開催日が近い順。開催日が取れなかったものは末尾に回す（MySQL は NULL が先頭に来るため）。
  scope :upcoming_first, -> { order(Arel.sql("starts_at IS NULL, starts_at ASC")) }

  # 検索結果（Research::BaseService#build_result）と同じキーで返す。
  # フロントが同じカードで描画できるようにするため、キー名を勝手に変えないこと。
  def to_result
    {
      site: site,
      siteLabel: site_label,
      title: title,
      url: url,
      # 検索結果と同じ JST 表記に揃える（DB は UTC で持つため、そのまま返すと表記だけ変わってしまう）
      startsAt: starts_at&.getlocal(Research::DateRange::JST_OFFSET)&.iso8601,
      datetimeText: datetime_text,
      venue: venue,
      address: address,
      organizer: organizer,
      participants: participants,
      capacity: capacity,
      imageUrl: image_url,
      favoritedAt: created_at&.iso8601
    }
  end
end
