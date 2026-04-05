class CreateGithubReviews < ActiveRecord::Migration[7.2]
  def change
    create_table :github_reviews do |t|
      t.string :github_url, null: false
      t.string :github_type        # 'pr', 'issue', 'repo', 'commit'
      t.string :repo_full_name     # 'owner/repo'
      t.integer :pr_number
      t.string :author             # コミュニティ投稿者名
      t.string :onclass_post_id    # オンクラスの投稿識別子
      t.string :item_id            # 受講生サポートの item_id
      t.string :status, default: 'pending' # pending, reviewed, approved, posted
      t.text :review_content       # レビュー内容
      t.text :github_comment_url   # 投稿済みコメントURL
      t.text :images               # 検出した画像URL (JSON array)
      t.integer :user_id
      t.datetime :reviewed_at
      t.datetime :posted_at
      t.timestamps
    end

    add_index :github_reviews, :github_url, unique: true
    add_index :github_reviews, :item_id
    add_index :github_reviews, :status
  end
end
