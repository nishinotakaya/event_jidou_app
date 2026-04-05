class AddRegistrationsToPostingHistories < ActiveRecord::Migration[7.2]
  def change
    add_column :posting_histories, :registrations, :integer
    add_column :posting_histories, :registrations_checked_at, :datetime
  end
end
