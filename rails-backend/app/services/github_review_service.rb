require 'net/http'
require 'json'
require 'uri'

class GithubReviewService
  GITHUB_API = 'https://api.github.com'.freeze

  def initialize(logger: nil)
    @logger = logger || Rails.logger
    creds = ServiceConnection.credentials_for('github')
    @github_token = creds[:token].presence || ENV['GITHUB_TOKEN']
    @openai_key = AppSetting.find_by(key: 'openai_api_key')&.value || ENV['OPENAI_API_KEY']
  end

  # GitHub URLからコードレビューを生成
  def review(github_url)
    parsed = parse_github_url(github_url)
    raise "GitHub URLの解析に失敗: #{github_url}" unless parsed

    case parsed[:type]
    when 'pr'
      review_pull_request(parsed)
    when 'commit'
      review_commit(parsed)
    when 'repo'
      review_repository(parsed)
    when 'issue'
      review_issue(parsed)
    else
      raise "未対応のGitHub URLタイプ: #{parsed[:type]}"
    end
  end

  # GitHubにコメントを投稿（ローカル画像はGitHubにアップロードして差し替え）
  def post_comment(github_url, comment_body)
    raise 'GITHUB_TOKENが設定されていません' unless @github_token.present?

    parsed = parse_github_url(github_url)
    raise "GitHub URLの解析に失敗" unless parsed

    # ローカル画像URL（/uploads/xxx.png）をGitHubにアップロードして差し替え
    processed_body = upload_local_images(comment_body, parsed)

    case parsed[:type]
    when 'pr'
      post_pr_comment(parsed[:owner], parsed[:repo], parsed[:number], processed_body)
    when 'issue'
      post_issue_comment(parsed[:owner], parsed[:repo], parsed[:number], processed_body)
    when 'commit'
      post_commit_comment(parsed[:owner], parsed[:repo], parsed[:sha], processed_body)
    else
      raise "コメント投稿に対応していないURLタイプ: #{parsed[:type]}"
    end
  end

  private

  # URL解析: github.com/owner/repo/pull/123 など
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

  # PR レビュー
  def review_pull_request(parsed)
    pr_data = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}/pulls/#{parsed[:number]}")
    diff = github_get_raw("/repos/#{parsed[:owner]}/#{parsed[:repo]}/pulls/#{parsed[:number]}", accept: 'application/vnd.github.v3.diff')
    files = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}/pulls/#{parsed[:number]}/files")

    # 画像ファイルを検出
    images = detect_images(files)

    context = <<~CTX
      ## PR情報
      - タイトル: #{pr_data['title']}
      - 作成者: #{pr_data.dig('user', 'login')}
      - ブランチ: #{pr_data['head']&.dig('ref')} → #{pr_data['base']&.dig('ref')}
      - 変更ファイル数: #{files.length}

      ## 変更ファイル一覧
      #{files.map { |f| "- #{f['filename']} (+#{f['additions']} -#{f['deletions']})" }.join("\n")}

      ## Diff（先頭8000文字）
      ```diff
      #{diff.to_s[0..8000]}
      ```
    CTX

    review_content = generate_ai_review(context, pr_data['title'])

    {
      type: 'pr',
      title: pr_data['title'],
      author: pr_data.dig('user', 'login'),
      review: review_content,
      images: images,
      repo_full_name: "#{parsed[:owner]}/#{parsed[:repo]}",
      number: parsed[:number],
    }
  end

  # コミットレビュー
  def review_commit(parsed)
    commit = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}/commits/#{parsed[:sha]}")
    files = commit['files'] || []
    images = detect_images(files)

    context = <<~CTX
      ## コミット情報
      - メッセージ: #{commit.dig('commit', 'message')}
      - 作成者: #{commit.dig('commit', 'author', 'name')}
      - 変更ファイル数: #{files.length}

      ## 変更ファイル一覧
      #{files.map { |f| "- #{f['filename']} (+#{f['additions']} -#{f['deletions']})" }.join("\n")}

      ## パッチ（先頭8000文字）
      #{files.map { |f| "### #{f['filename']}\n```diff\n#{f['patch']}\n```" }.join("\n")[0..8000]}
    CTX

    review_content = generate_ai_review(context, commit.dig('commit', 'message'))

    {
      type: 'commit',
      title: commit.dig('commit', 'message')&.lines&.first&.strip,
      author: commit.dig('commit', 'author', 'name'),
      review: review_content,
      images: images,
      repo_full_name: "#{parsed[:owner]}/#{parsed[:repo]}",
    }
  end

  # リポジトリ概要レビュー
  def review_repository(parsed)
    repo = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}")
    readme_data = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}/readme") rescue nil
    readme = readme_data ? Base64.decode64(readme_data['content']).force_encoding('UTF-8') : ''
    recent_commits = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}/commits?per_page=10") rescue []

    context = <<~CTX
      ## リポジトリ情報
      - リポジトリ: #{repo['full_name']}
      - 説明: #{repo['description']}
      - 言語: #{repo['language']}
      - スター: #{repo['stargazers_count']}

      ## README（先頭3000文字）
      #{readme[0..3000]}

      ## 最近のコミット
      #{recent_commits.first(5).map { |c| "- #{c.dig('commit', 'message')&.lines&.first&.strip} (#{c.dig('commit', 'author', 'name')})" }.join("\n")}
    CTX

    review_content = generate_ai_review(context, repo['full_name'], type: 'repo')

    {
      type: 'repo',
      title: repo['full_name'],
      author: repo.dig('owner', 'login'),
      review: review_content,
      images: [],
      repo_full_name: repo['full_name'],
    }
  end

  # Issue レビュー
  def review_issue(parsed)
    issue = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}/issues/#{parsed[:number]}")

    context = <<~CTX
      ## Issue情報
      - タイトル: #{issue['title']}
      - 作成者: #{issue.dig('user', 'login')}
      - ラベル: #{issue['labels']&.map { |l| l['name'] }&.join(', ')}
      - 本文: #{issue['body'].to_s[0..3000]}
    CTX

    review_content = generate_ai_review(context, issue['title'], type: 'issue')

    {
      type: 'issue',
      title: issue['title'],
      author: issue.dig('user', 'login'),
      review: review_content,
      images: [],
      repo_full_name: "#{parsed[:owner]}/#{parsed[:repo]}",
      number: parsed[:number],
    }
  end

  # AI（OpenAI）によるコードレビュー生成
  def generate_ai_review(context, title, type: 'code')
    raise 'OpenAI APIキーが設定されていません' unless @openai_key.present?

    system_prompt = case type
    when 'repo'
      <<~PROMPT
        あなたはプログラミングスクールの講師です。受講生が作成したリポジトリをレビューしてください。
        以下の観点でフィードバックを書いてください：
        1. 全体構成の良い点
        2. 改善できるポイント（具体的に）
        3. 次のステップとして取り組むと良いこと
        日本語で、受講生を励ますトーンで書いてください。
      PROMPT
    when 'issue'
      <<~PROMPT
        あなたはプログラミングスクールの講師です。受講生が作成したIssueをレビューしてください。
        Issue の書き方、問題の整理の仕方について良い点と改善点をフィードバックしてください。
        日本語で、受講生を励ますトーンで書いてください。
      PROMPT
    else
      <<~PROMPT
        あなたはプログラミングスクールの講師です。受講生が書いたコードをレビューしてください。
        以下の観点でフィードバックを書いてください：
        1. コードの良い点（具体的なファイル・行を参照）
        2. 改善提案（バグ、パフォーマンス、可読性、セキュリティ）
        3. 学習のヒント・次のステップ
        日本語で、受講生を励ますトーンで書いてください。マークダウン形式で出力してください。
      PROMPT
    end

    uri = URI('https://api.openai.com/v1/chat/completions')
    body = {
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: "「#{title}」のレビューをお願いします。\n\n#{context}" },
      ],
      max_tokens: 2000,
      temperature: 0.7,
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{@openai_key}"
    req['Content-Type'] = 'application/json'
    req.body = body.to_json

    res = http.request(req)
    data = JSON.parse(res.body)
    data.dig('choices', 0, 'message', 'content') || 'レビュー生成に失敗しました'
  end

  # 変更ファイルから画像を検出
  def detect_images(files)
    image_exts = %w[.png .jpg .jpeg .gif .svg .webp .ico]
    files.select { |f| image_exts.any? { |ext| f['filename'].downcase.end_with?(ext) } }
         .map { |f| { filename: f['filename'], status: f['status'], raw_url: f['raw_url'] } }
  end

  # GitHub API GET
  def github_get(path)
    uri = URI("#{GITHUB_API}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri)
    req['Accept'] = 'application/vnd.github.v3+json'
    req['Authorization'] = "Bearer #{@github_token}" if @github_token.present?
    req['User-Agent'] = 'OnClass-Review-Bot'

    res = http.request(req)
    JSON.parse(res.body)
  end

  # GitHub API GET (raw)
  def github_get_raw(path, accept: 'text/plain')
    uri = URI("#{GITHUB_API}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri)
    req['Accept'] = accept
    req['Authorization'] = "Bearer #{@github_token}" if @github_token.present?
    req['User-Agent'] = 'OnClass-Review-Bot'

    res = http.request(req)
    res.body
  end

  # PRにコメント投稿
  def post_pr_comment(owner, repo, number, body)
    github_post("/repos/#{owner}/#{repo}/issues/#{number}/comments", { body: body })
  end

  # Issueにコメント投稿
  def post_issue_comment(owner, repo, number, body)
    github_post("/repos/#{owner}/#{repo}/issues/#{number}/comments", { body: body })
  end

  # コミットにコメント投稿
  def post_commit_comment(owner, repo, sha, body)
    github_post("/repos/#{owner}/#{repo}/commits/#{sha}/comments", { body: body })
  end

  # GitHub API POST
  def github_post(path, data)
    uri = URI("#{GITHUB_API}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri)
    req['Accept'] = 'application/vnd.github.v3+json'
    req['Authorization'] = "Bearer #{@github_token}"
    req['User-Agent'] = 'OnClass-Review-Bot'
    req['Content-Type'] = 'application/json'
    req.body = data.to_json

    res = http.request(req)
    result = JSON.parse(res.body)
    raise "GitHub APIエラー: #{result['message']}" unless res.code.start_with?('2')
    result
  end

  # ローカル画像URL（/uploads/xxx.png）をGitHubにアップロードして差し替え
  def upload_local_images(body, parsed)
    result = body.dup
    local_pattern = %r{!\[([^\]]*)\]\((/uploads/[^\)]+)\)}

    result.gsub(local_pattern) do
      alt = $1
      local_path = $2
      full_path = Rails.root.join('public', local_path.sub(%r{^/}, '')).to_s

      if File.exist?(full_path)
        begin
          github_url = upload_image_to_github(full_path, parsed)
          "![#{alt}](#{github_url})"
        rescue => e
          Rails.logger.warn "[Image Upload] #{e.message}"
          "![#{alt}](#{local_path})"
        end
      else
        "![#{alt}](#{local_path})"
      end
    end
  end

  # 画像をGitHub Contents APIでアップロード
  def upload_image_to_github(file_path, parsed)
    content_b64 = Base64.strict_encode64(File.binread(file_path))
    filename = "review_images/#{File.basename(file_path)}"

    # 既存ファイルのSHAを取得（上書き用）
    existing_sha = nil
    begin
      existing = github_get("/repos/#{parsed[:owner]}/#{parsed[:repo]}/contents/#{filename}")
      existing_sha = existing['sha'] if existing.is_a?(Hash)
    rescue
      # ファイルが存在しない場合は無視
    end

    uri = URI("#{GITHUB_API}/repos/#{parsed[:owner]}/#{parsed[:repo]}/contents/#{filename}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Put.new(uri)
    req['Authorization'] = "Bearer #{@github_token}"
    req['Accept'] = 'application/vnd.github.v3+json'
    req['Content-Type'] = 'application/json'
    req['User-Agent'] = 'OnClass-Review-Bot'

    body = { message: "📸 レビュー画像追加: #{File.basename(file_path)}", content: content_b64 }
    body[:sha] = existing_sha if existing_sha
    req.body = body.to_json

    res = http.request(req)
    unless res.code.start_with?('2')
      # masterブランチで再試行
      body[:branch] = 'master'
      req.body = body.to_json
      res = http.request(req)
    end

    data = JSON.parse(res.body)
    data.dig('content', 'download_url') || raise("アップロード失敗: #{data['message']}")
  end
end
