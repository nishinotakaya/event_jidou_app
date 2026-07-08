class AllowNullWeekdayOnMeetingNotifications < ActiveRecord::Migration[7.2]
  def change
    # 曜日「設定なし」(nil) を許可する。nil の場合は自動送信しない（手動送信専用）。
    change_column_null :meeting_notifications, :weekday, true
    change_column_default :meeting_notifications, :weekday, from: 0, to: nil
  end
end
