class GithubReviewScanJob < ApplicationJob
  queue_as :default

  CLAUDE_CLI = File.expand_path('~/.local/bin/claude').freeze

  # GitHubスキャンボタンから呼ばれる全自動フロー:
  # 1. オンクラス メンションスキャン → 未対応GitHub URL検出
  # 2. ローカルリポジトリ セットアップ（clone/pull + VS Code起動）
  # 3. Claude Code CLIでコードレビュー
  # 4. レビューを .md保存 + 受講生サポートに起票
  def perform(job_id = nil)
    broadcast(job_id, type: 'log', message: '🔍 オンクラス コミュニティスキャン開始...')
    user = User.find_by(email: 'takaya314boxing@gmail.com')
    return broadcast(job_id, type: 'error', message: 'ユーザーが見つかりません') unless user

    # 1. コミュニティスキャン
    scanner = OnclassCommunityScanner.new(logger: Rails.logger)
    new_posts = scanner.scan
    broadcast(job_id, type: 'log', message: "📡 #{new_posts.length}件の未対応GitHub URLを検出")

    if new_posts.empty?
      broadcast(job_id, type: 'done', message: '✅ 未対応のGitHub URLはありません')
      return
    end

    repo_service = LocalRepoService.new(logger: Rails.logger)

    new_posts.each do |post|
      begin
        # DB登録
        review = GithubReview.find_or_create_by(github_url: post[:url]) do |r|
          r.status = 'pending'
          r.author = post[:author]
          r.onclass_post_id = post[:post_id]
          r.images = (post[:images] || []).to_json
          r.user = user
        end

        next unless review.status == 'pending'

        parsed = parse_github_url(post[:url])
        if parsed
          review.update!(
            github_type: parsed[:type],
            repo_full_name: "#{parsed[:owner]}/#{parsed[:repo]}",
            pr_number: parsed[:number],
          )
        end

        broadcast(job_id, type: 'log', message: "🆕 #{post[:url]}")

        # 2. ローカルリポジトリ セットアップ
        local_path = nil
        begin
          repo_result = repo_service.setup_and_open(post[:url], author_name: post[:author])
          local_path = repo_result[:path]
          broadcast(job_id, type: 'log', message: "📂 #{repo_result[:action]}: #{local_path}")
        rescue => e
          broadcast(job_id, type: 'log', message: "⚠️ ローカルセットアップ失敗: #{e.message}")
        end

        # 3. 動作テスト実行 + スクリーンショット
        test_result = nil
        screenshots = []
        if local_path.present? && Dir.exist?(local_path.to_s)
          broadcast(job_id, type: 'log', message: "🧪 動作テスト実行中...")
          test_result = run_tests(local_path)
          broadcast(job_id, type: 'log', message: test_result[:passed] ? "✅ テスト成功" : "❌ テスト失敗: #{test_result[:summary]}")

          # テスト失敗時またはアプリ起動可能時にスクリーンショット
          unless test_result[:passed]
            broadcast(job_id, type: 'log', message: "📸 スクリーンショット撮影中...")
            screenshots = take_screenshots(local_path, post[:url])
            broadcast(job_id, type: 'log', message: "📸 #{screenshots.length}枚のスクリーンショットを保存")
          end
        end

        # 4. Claude Code CLIでレビュー
        broadcast(job_id, type: 'log', message: "🤖 Claude Code レビュー中: #{post[:url]}")
        review_content = run_claude_review(post[:url], local_path, parsed)

        if review_content.present?
          # テスト結果をレビューに追加
          if test_result
            review_content += "\n\n---\n\n## 動作テスト結果\n\n"
            review_content += test_result[:passed] ? "✅ **テスト成功**\n" : "❌ **テスト失敗**\n"
            review_content += "```\n#{test_result[:output].to_s[0..2000]}\n```\n" unless test_result[:passed]
          end

          # スクリーンショットパスをレビューに追加
          if screenshots.any?
            review_content += "\n\n## スクリーンショット\n\n"
            screenshots.each { |ss| review_content += "📸 `#{ss}`\n" }
          end

          # 5a. .md ファイルに保存
          md_path = save_review_md(local_path, review_content, parsed)
          broadcast(job_id, type: 'log', message: "📝 レビュー保存: #{md_path}") if md_path

          # 5b. スクリーンショットをGitHubにアップロード（GITHUB_TOKENがある場合）
          screenshot_urls = []
          if screenshots.any? && ENV['GITHUB_TOKEN'].present? && parsed
            broadcast(job_id, type: 'log', message: "📤 スクリーンショットをGitHubにアップロード中...")
            screenshot_urls = upload_screenshots_to_github(screenshots, parsed)
          end

          # 5c. 受講生サポートに起票
          content_with_images = build_item_content(post, review_content, local_path)
          screenshot_urls.each { |url| content_with_images += "\n![screenshot](#{url})" }

          item = Item.create!(
            item_type: 'student',
            name: "📝 コードレビュー: #{build_title(parsed, post)}",
            content: content_with_images,
            folder: 'Gitレビュー',
            user_id: user.id,
            student_post_type: '受講生告知',
          )

          review.update!(
            status: 'reviewed',
            review_content: review_content,
            item_id: item.id,
            images: (screenshots + screenshot_urls).to_json,
            reviewed_at: Time.current,
          )

          broadcast(job_id, type: 'log', message: "✅ 起票完了: #{item.name}")
        else
          broadcast(job_id, type: 'log', message: "⚠️ レビュー生成に失敗しました")
        end

      rescue => e
        broadcast(job_id, type: 'log', message: "❌ #{post[:url]}: #{e.message}")
      end
    end

    broadcast(job_id, type: 'done', message: "✅ #{new_posts.length}件のレビュー完了")
  end

  private

  # Claude Code CLI でレビューを実行
  def run_claude_review(github_url, local_path, parsed)
    prompt = build_review_prompt(github_url, parsed)

    # ローカルリポジトリがあればそのディレクトリで実行（コード参照可能）
    work_dir = local_path.present? && Dir.exist?(local_path.to_s) ? local_path : Dir.tmpdir

    cmd = [
      CLAUDE_CLI, '-p',
      '--output-format', 'text',
      '--max-turns', '10',
      prompt,
    ]

    Rails.logger.info "[Claude Review] dir=#{work_dir}, url=#{github_url}"

    result = nil
    IO.popen(cmd, chdir: work_dir, err: [:child, :out]) do |io|
      result = io.read
    end

    if $?.success? && result.present?
      Rails.logger.info "[Claude Review] 成功: #{result.length}文字"
      result.strip
    else
      Rails.logger.error "[Claude Review] 失敗: exit=#{$?.exitstatus}"
      nil
    end
  rescue => e
    Rails.logger.error "[Claude Review] エラー: #{e.message}"
    nil
  end

  def build_review_prompt(github_url, parsed)
    type_label = case parsed&.dig(:type)
                 when 'pr' then "PR ##{parsed[:number]}"
                 when 'issue' then "Issue ##{parsed[:number]}"
                 when 'commit' then "コミット"
                 else "リポジトリ"
                 end

    <<~PROMPT
      あなたはプログラミングスクールの講師です。
      以下のGitHub #{type_label}をレビューしてください。

      URL: #{github_url}

      このディレクトリにリポジトリのコードがあります。全ファイルを読んでレビューしてください。

      ## レビュー観点（必ず全て確認すること）

      ### A. データの整合性・競合
      - 非同期読み込み完了前にstate初期値で保存が走りデータが消えないか
      - useEffectの依存配列に漏れがないか（画面遷移後に古いデータが残る問題）
      - 二重保存（useEffect自動保存 + ハンドラ内手動保存の重複）
      - ID採番の衝突（表示中データだけからMax IDを取っていないか）
      - 型安全でないデータ読み込み（Array.isArrayチェックなしのキャスト）

      ### B. 状態管理
      - 制御コンポーネント vs 非制御（defaultValue vs value）
      - リロード後のstate復元（フィルタ・ソートがリロードで消えないか）
      - setStateの非同期性（setState直後に新しい値を使っていないか）

      ### C. バリデーション・エッジケース
      - 不正な入力値（URLクエリ ?date=invalid でInvalid Date / NaNにならないか）
      - 配列でないデータによる .map is not a function エラー
      - 境界値（空配列、undefined、日付の前月末・翌月初）

      ### D. コード品質
      - console.log のデバッグ出力が残っていないか
      - コメントアウトされた関数ブロック（Git履歴で復元可能なので削除推奨）
      - 1ファイル300行以上ならコンポーネント分割を提案
      - 型定義がコンポーネント内にあれば types.ts への分離を提案

      ### E. パフォーマンス
      - useMemoなしのソート・フィルタが毎レンダリングで走っていないか
      - 全キースキャンしていないか（インデックス推奨）

      ### F. フレームワーク固有
      - DOM直接操作よりライブラリのコールバック（dateClick等）を使うべき箇所
      - React Router の useLocation/useNavigate の適切な使用

      ## 出力フォーマット

      各指摘は以下の形式で書くこと：

      ## N. 指摘タイトル

      **現象:** ユーザーから見てどう困るか
      **場所:** `ファイルパス` の N〜M 行目
      **原因:** なぜそうなるかの技術的説明

      **該当コード:**
      ```
      問題のコード断片
      ```

      **対策案:**
      ```
      修正後のコード例
      ```

      ---

      最後に「良い点」と「学習のヒント」もまとめて書く。
      受講生を励ますトーンで。厳しすぎず、ただし具体的に。
    PROMPT
  end

  # レビューを .md ファイルに保存
  def save_review_md(local_path, content, parsed)
    return nil unless local_path.present? && Dir.exist?(local_path.to_s)

    filename = "REVIEW_#{Time.current.strftime('%Y%m%d_%H%M%S')}.md"
    filepath = File.join(local_path, filename)

    File.write(filepath, "# コードレビュー\n\n#{content}\n\n---\n_Generated by Claude Code at #{Time.current.strftime('%Y-%m-%d %H:%M')}_\n")
    filepath
  end

  def build_title(parsed, post)
    if parsed
      "#{parsed[:owner]}/#{parsed[:repo]}#{parsed[:number] ? " ##{parsed[:number]}" : ''}"
    else
      post[:url].to_s[0..60]
    end
  end

  def build_item_content(post, review_content, local_path)
    lines = []
    lines << "🔗 GitHub: #{post[:url]}"
    lines << "👤 投稿者: #{post[:author]}" if post[:author].present?
    lines << "📂 ローカル: #{local_path}" if local_path.present?
    lines << ""
    lines << "---"
    lines << ""
    lines << review_content
    lines.join("\n")
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

  # 動作テスト実行
  def run_tests(local_path)
    pkg_path = File.join(local_path, 'package.json')
    gemfile_path = File.join(local_path, 'Gemfile')

    if File.exist?(pkg_path)
      run_node_tests(local_path, pkg_path)
    elsif File.exist?(gemfile_path)
      run_rails_tests(local_path)
    else
      { passed: true, summary: 'テスト対象なし', output: '' }
    end
  end

  def run_node_tests(local_path, pkg_path)
    pkg = JSON.parse(File.read(pkg_path)) rescue {}
    scripts = pkg['scripts'] || {}

    # テストコマンド判定
    test_cmd = if scripts['test'] && !scripts['test'].include?('no test specified')
                 'npm test -- --run 2>&1'
               elsif scripts['lint']
                 'npm run lint 2>&1'
               elsif scripts['build']
                 'npm run build 2>&1'
               else
                 nil
               end

    return { passed: true, summary: 'テストスクリプトなし', output: '' } unless test_cmd

    # npm install が必要な場合
    unless Dir.exist?(File.join(local_path, 'node_modules'))
      system("cd \"#{local_path}\" && npm install > /dev/null 2>&1")
    end

    output = `cd "#{local_path}" && #{test_cmd}`
    passed = $?.success?
    summary = passed ? 'PASS' : output.lines.last(3).join.strip[0..200]

    { passed: passed, summary: summary, output: output }
  rescue => e
    { passed: false, summary: e.message, output: e.message }
  end

  def run_rails_tests(local_path)
    output = `cd "#{local_path}" && bundle exec rails test 2>&1`
    passed = $?.success?
    { passed: passed, summary: passed ? 'PASS' : output.lines.last(5).join.strip[0..200], output: output }
  rescue => e
    { passed: false, summary: e.message, output: e.message }
  end

  # Playwrightでスクリーンショット撮影
  def take_screenshots(local_path, github_url)
    screenshots = []
    ss_dir = File.join(local_path, 'review_screenshots')
    FileUtils.mkdir_p(ss_dir)

    # アプリのポートを検出（vite: 5173, CRA: 3000, Rails: 3000）
    ports = [5173, 3000, 3001, 4173, 8080]
    app_url = nil
    ports.each do |port|
      begin
        uri = URI("http://localhost:#{port}")
        Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) { |http| http.get('/') }
        app_url = "http://localhost:#{port}"
        break
      rescue
        next
      end
    end

    # アプリが起動していない場合、起動を試みる
    unless app_url
      pkg_path = File.join(local_path, 'package.json')
      if File.exist?(pkg_path)
        pid = spawn("cd \"#{local_path}\" && npm run dev", [:out, :err] => '/dev/null')
        Process.detach(pid)
        sleep(5)
        ports.each do |port|
          begin
            Net::HTTP.start('localhost', port, open_timeout: 1, read_timeout: 1) { |http| http.get('/') }
            app_url = "http://localhost:#{port}"
            break
          rescue
            next
          end
        end
      end
    end

    return screenshots unless app_url

    require 'playwright'
    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: true)
      page = browser.new_page(viewport: { width: 1280, height: 800 })

      begin
        # トップページ
        page.goto(app_url, timeout: 15_000, waitUntil: 'networkidle')
        page.wait_for_timeout(2000)
        ss_path = File.join(ss_dir, 'top.png')
        page.screenshot(path: ss_path)
        screenshots << ss_path

        # コンソールエラーがあればキャプチャ
        errors = []
        page.on('console', ->(msg) { errors << msg.text if msg.type == 'error' })
        page.on('pageerror', ->(err) { errors << err.message })

        # ページ内のリンクを1つクリックしてスクリーンショット
        links = page.evaluate('Array.from(document.querySelectorAll("a[href]")).map(a => a.href).filter(h => h.startsWith(window.location.origin)).slice(0, 3)')
        links.each_with_index do |link, i|
          begin
            page.goto(link, timeout: 10_000, waitUntil: 'networkidle')
            page.wait_for_timeout(1500)
            ss_path = File.join(ss_dir, "page_#{i + 1}.png")
            page.screenshot(path: ss_path)
            screenshots << ss_path
          rescue
            next
          end
        end

        # エラーがあればエラー画面のスクリーンショット
        if errors.any?
          ss_path = File.join(ss_dir, 'errors.png')
          page.screenshot(path: ss_path)
          screenshots << ss_path
        end
      ensure
        browser.close
      end
    end

    screenshots
  rescue => e
    Rails.logger.warn "[Screenshot] #{e.message}"
    screenshots
  end

  # スクリーンショットをGitHub Issueコメント経由でアップロード
  def upload_screenshots_to_github(screenshots, parsed)
    urls = []
    token = ENV['GITHUB_TOKEN']
    return urls unless token.present? && parsed

    screenshots.each do |ss_path|
      next unless File.exist?(ss_path)
      begin
        # GitHubのリポジトリにファイルをコミット（reviewブランチに）
        content_b64 = Base64.strict_encode64(File.read(ss_path))
        filename = "review_screenshots/#{File.basename(ss_path)}"

        uri = URI("https://api.github.com/repos/#{parsed[:owner]}/#{parsed[:repo]}/contents/#{filename}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        req = Net::HTTP::Put.new(uri)
        req['Authorization'] = "Bearer #{token}"
        req['Accept'] = 'application/vnd.github.v3+json'
        req['Content-Type'] = 'application/json'
        req['User-Agent'] = 'OnClass-Review-Bot'
        req.body = {
          message: "📸 レビュースクリーンショット追加: #{File.basename(ss_path)}",
          content: content_b64,
          branch: 'main',
        }.to_json

        res = http.request(req)
        if res.code.start_with?('2')
          data = JSON.parse(res.body)
          urls << data.dig('content', 'download_url')
          Rails.logger.info "[GitHub Upload] #{filename} → #{urls.last}"
        else
          # mainブランチがない場合はmasterで再試行
          req.body = { message: "📸 レビュースクリーンショット追加", content: content_b64, branch: 'master' }.to_json
          res = http.request(req)
          if res.code.start_with?('2')
            data = JSON.parse(res.body)
            urls << data.dig('content', 'download_url')
          end
        end
      rescue => e
        Rails.logger.warn "[GitHub Upload] #{e.message}"
      end
    end

    urls
  end

  def broadcast(job_id, data)
    return unless job_id
    ActionCable.server.broadcast("post_#{job_id}", data)
  rescue => e
    Rails.logger.warn "[Broadcast] #{e.message}"
  end
end
