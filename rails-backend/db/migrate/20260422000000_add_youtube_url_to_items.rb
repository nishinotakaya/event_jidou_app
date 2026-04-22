class AddYoutubeUrlToItems < ActiveRecord::Migration[7.2]
  def change
    add_column :items, :youtube_url, :string
  end
end
