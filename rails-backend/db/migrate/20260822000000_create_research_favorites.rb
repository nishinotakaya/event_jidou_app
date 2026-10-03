class CreateResearchFavorites < ActiveRecord::Migration[7.2]
  def change
    # 交流会リサーチで星を付けたイベント（ユーザーごと）。
    # 検索結果は毎回サイトから取り直すため、星を付けた時点の表示内容をそのまま持たせる。
    # そうしないと「あとで見返したいイベント」がキーワードや掲載期間の都合で二度と出てこなくなる。
    create_table :research_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.string :url,          null: false, limit: 512  # サイト上のイベントURL（ユーザー内で一意）
      t.string :site,         null: false              # ResearchController::SERVICES のキー
      t.string :site_label
      t.text   :title,        null: false
      t.datetime :starts_at                            # 開催日時（不明なサイトもあるので null 可）
      t.string :datetime_text                          # サイト表記のままの日時（"開催日:8/26" など）
      t.text   :venue
      t.text   :address
      t.string :organizer
      t.integer :participants
      t.integer :capacity
      t.text :image_url
      t.timestamps
    end

    add_index :research_favorites, %i[user_id url], unique: true
  end
end
