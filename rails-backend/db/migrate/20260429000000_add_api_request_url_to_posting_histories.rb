class AddApiRequestUrlToPostingHistories < ActiveRecord::Migration[7.2]
  def change
    add_column :posting_histories, :api_request_url, :string
  end
end
