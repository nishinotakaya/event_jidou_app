class ChangeAppSettingsValueToMediumtext < ActiveRecord::Migration[7.1]
  def up
    # Base64 化したアイコン (256x256/JPEG, ~40KB → Base64 で ~55KB) を格納するため、
    # MySQL の text(64KB) から mediumtext(16MB) へ拡張する。
    change_column :app_settings, :value, :mediumtext
  end

  def down
    change_column :app_settings, :value, :text
  end
end
