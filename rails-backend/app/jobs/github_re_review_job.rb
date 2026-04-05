class GithubReReviewJob < ApplicationJob
  queue_as :default

  CLAUDE_CLI = File.expand_path('~/.local/bin/claude').freeze

  def perform(job_id, review_id)
    review = GithubReview.find(review_id)
    broadcast(job_id, type: 'log', message: "🔄 再レビュー開始: #{review.github_url}")

    repo_service = LocalRepoService.new(logger: Rails.logger)

    # 1. ローカルリポジトリ更新
    local_path = nil
    begin
      result = repo_service.setup_and_open(review.github_url, author_name: review.author)
      local_path = result[:path]
      broadcast(job_id, type: 'log', message: "📂 #{result[:action]}: #{local_path}")
    rescue => e
      broadcast(job_id, type: 'log', message: "⚠️ ローカルセットアップ: #{e.message}")
    end

    # 2. 動作テスト
    test_result = nil
    screenshots = []
    if local_path.present? && Dir.exist?(local_path.to_s)
      broadcast(job_id, type: 'log', message: "🧪 動作テスト実行中...")
      scan_job = GithubReviewScanJob.new
      test_result = scan_job.send(:run_tests, local_path)
      broadcast(job_id, type: 'log', message: test_result[:passed] ? "✅ テスト成功" : "❌ テスト失敗")

      unless test_result[:passed]
        broadcast(job_id, type: 'log', message: "📸 スクリーンショット撮影中...")
        screenshots = scan_job.send(:take_screenshots, local_path, review.github_url)
        broadcast(job_id, type: 'log', message: "📸 #{screenshots.length}枚")
      end
    end

    # 3. Claude Code レビュー
    broadcast(job_id, type: 'log', message: "🤖 Claude Code レビュー中...")
    parsed = parse_github_url(review.github_url)
    review_content = run_claude_review(review.github_url, local_path, parsed)

    unless review_content.present?
      broadcast(job_id, type: 'error', message: "レビュー生成に失敗しました")
      return
    end

    # テスト結果を追加
    if test_result
      review_content += "\n\n---\n\n## 動作テスト結果\n\n"
      review_content += test_result[:passed] ? "✅ **テスト成功**\n" : "❌ **テスト失敗**\n```\n#{test_result[:output].to_s[0..2000]}\n```\n"
    end

    if screenshots.any?
      review_content += "\n\n## スクリーンショット\n\n"
      screenshots.each { |ss| review_content += "📸 `#{ss}`\n" }
    end

    # 4. 保存
    scan_job_instance = GithubReviewScanJob.new
    md_path = scan_job_instance.send(:save_review_md, local_path, review_content, parsed)
    broadcast(job_id, type: 'log', message: "📝 #{md_path}") if md_path

    # 既存のitemを更新（あれば）、なければ新規作成
    if review.item_id.present?
      item = Item.find_by(id: review.item_id)
      if item
        item.update!(content: "🔗 GitHub: #{review.github_url}\n📂 ローカル: #{local_path}\n\n---\n\n#{review_content}")
      end
    else
      user = review.user || User.find_by(email: 'takaya314boxing@gmail.com')
      item = Item.create!(
        item_type: 'student',
        name: "📝 コードレビュー: #{review.repo_full_name || review.github_url[0..40]}",
        content: "🔗 GitHub: #{review.github_url}\n📂 ローカル: #{local_path}\n\n---\n\n#{review_content}",
        folder: 'Gitレビュー',
        user_id: user.id,
        student_post_type: '受講生告知',
      )
      review.item_id = item.id
    end

    review.update!(
      status: 'reviewed',
      review_content: review_content,
      reviewed_at: Time.current,
    )

    broadcast(job_id, type: 'done', message: "✅ 再レビュー完了: #{review.repo_full_name}")
  rescue => e
    broadcast(job_id, type: 'error', message: "❌ #{e.message}")
  end

  private

  def run_claude_review(github_url, local_path, parsed)
    scan_job = GithubReviewScanJob.new
    scan_job.send(:run_claude_review, github_url, local_path, parsed)
  end

  def parse_github_url(url)
    case url
    when %r{github\.com/([^/]+)/([^/]+)/pull/(\d+)}
      { type: 'pr', owner: $1, repo: $2, number: $3.to_i }
    when %r{github\.com/([^/]+)/([^/]+)/issues/(\d+)}
      { type: 'issue', owner: $1, repo: $2, number: $3.to_i }
    when %r{github\.com/([^/]+)/([^/]+)/commit/([0-9a-f]+)}
      { type: 'commit', owner: $1, repo: $2, sha: $3 }
    when %r{github\.com/([^/]+)/([^/]+?)(?:\.git)?(?:/tree/[^/]+)?/?$}
      { type: 'repo', owner: $1, repo: $2 }
    end
  end

  def broadcast(job_id, data)
    return unless job_id
    ActionCable.server.broadcast("post_#{job_id}", data)
  rescue => e
    Rails.logger.warn "[Broadcast] #{e.message}"
  end
end
