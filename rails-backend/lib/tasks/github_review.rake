namespace :github do
  desc 'オンクラスコミュニティをスキャンしてGitHub URLを検出（レビューはClaude Codeで実行）'
  task scan: :environment do
    puts "=== オンクラス コミュニティスキャン ==="
    scanner = OnclassCommunityScanner.new(logger: Logger.new(STDOUT))
    results = scanner.scan

    if results.empty?
      puts "✅ 未対応のGitHub URLはありません"
      next
    end

    user = User.find_by(email: 'takaya314boxing@gmail.com')

    results.each do |post|
      review = GithubReview.find_or_create_by(github_url: post[:url]) do |r|
        r.status = 'pending'
        r.author = post[:author]
        r.onclass_post_id = post[:post_id]
        r.user = user
      end
      puts "🆕 #{review.github_url} (status: #{review.status})"
    end

    puts "\n=== 検出完了: #{results.length}件 ==="
    puts "Claude Code でレビューを実行してください"
  end

  desc 'レビュー一覧を表示'
  task list: :environment do
    reviews = GithubReview.order(created_at: :desc).limit(20)
    reviews.each do |r|
      puts "#{r.status.ljust(10)} #{r.github_type.to_s.ljust(6)} #{r.github_url}"
      puts "           → item: #{r.item_id}" if r.item_id
      puts ""
    end
    puts "計 #{GithubReview.count} 件"
  end

  desc 'pendingのGitHub URLをJSON出力（Claude Code連携用）'
  task pending: :environment do
    reviews = GithubReview.where(status: 'pending')
    reviews.each do |r|
      puts r.github_url
    end
  end
end
