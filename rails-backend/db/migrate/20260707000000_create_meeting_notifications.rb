class CreateMeetingNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :meeting_notifications do |t|
      t.string  :name,            null: false           # チーム名（例: チームB）
      t.string  :onclass_channel, null: false           # 投稿先オンクラスチャンネル名
      t.string  :zoom_url,        null: false
      t.string  :meeting_id
      t.string  :passcode
      t.integer :weekday,         null: false, default: 0 # 0=日曜 … 6=土曜
      t.string  :start_time,      null: false, default: '22:00' # ミーティング開始(JST)
      t.string  :end_time,        default: '22:30'             # ミーティング終了(JST)
      t.string  :notify_time,     null: false, default: '19:30' # 通知送信時刻(JST)
      t.boolean :enabled,         null: false, default: true
      t.date    :last_sent_on                                   # 二重送信防止
      t.timestamps
    end

    add_index :meeting_notifications, %i[enabled weekday]
  end
end
