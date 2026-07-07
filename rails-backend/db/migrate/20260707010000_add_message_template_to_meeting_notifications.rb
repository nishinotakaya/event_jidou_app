class AddMessageTemplateToMeetingNotifications < ActiveRecord::Migration[7.2]
  def change
    add_column :meeting_notifications, :message_template, :text
  end
end
