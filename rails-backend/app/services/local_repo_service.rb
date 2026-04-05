class LocalRepoService
  BASE_DIR = File.expand_path('~/3.フロントコース_カリキュラムチェック').freeze

  def initialize(logger: nil)
    @logger = logger || Rails.logger
  end

  # GitHub URLに対応するローカルリポジトリを検索。なければクローン。
  # VS Code を開き、アプリを起動する。
  # Returns: { path:, action: 'pull' | 'clone', app_started: bool }
  def setup_and_open(github_url, author_name: nil)
    repo_info = parse_github_repo(github_url)
    raise "リポジトリURLの解析に失敗: #{github_url}" unless repo_info

    local_path = find_local_repo(repo_info[:clone_url])

    if local_path
      handle_existing_repo(local_path, repo_info)
    else
      handle_new_repo(repo_info, author_name)
    end
  end

  private

  # GitHub URLからオーナー/リポジトリ名を抽出
  def parse_github_repo(url)
    case url
    when %r{github\.com/([^/]+)/([^/]+?)(?:\.git)?(?:/(?:pull|issues|commit|tree|blob)/.+)?$}
      owner = $1
      repo = $2
      {
        owner: owner,
        repo: repo,
        clone_url: "https://github.com/#{owner}/#{repo}.git",
        https_url: "https://github.com/#{owner}/#{repo}",
      }
    end
  end

  # ベースディレクトリ配下で一致するリポジトリを検索
  def find_local_repo(clone_url)
    normalized = normalize_remote_url(clone_url)

    Dir.glob("#{BASE_DIR}/**/.git", File::FNM_DOTMATCH).each do |git_dir|
      repo_dir = File.dirname(git_dir)
      remote = `git -C "#{repo_dir}" remote get-url origin 2>/dev/null`.strip
      return repo_dir if normalize_remote_url(remote) == normalized
    end

    nil
  end

  # remote URL を正規化（https/ssh/末尾.git の差異を吸収）
  def normalize_remote_url(url)
    url.to_s
       .sub(%r{^git@github\.com:}, 'https://github.com/')
       .sub(/\.git$/, '')
       .downcase
       .strip
  end

  # 既存リポジトリ: git pull → VS Code → ブラウザ
  def handle_existing_repo(local_path, repo_info)
    log "📂 ローカルリポジトリ発見: #{local_path}"

    # git pull
    default_branch = detect_default_branch(local_path)
    pull_result = `git -C "#{local_path}" pull origin #{default_branch} 2>&1`
    log "🔄 git pull: #{pull_result.lines.last&.strip}"

    # VS Code を開く
    open_vscode(local_path)

    # ブラウザでGitHubページを開く
    open_browser(repo_info[:https_url])

    { path: local_path, action: 'pull', app_started: false }
  end

  # 新規リポジトリ: フォルダ作成 → clone → VS Code → アプリ起動
  def handle_new_repo(repo_info, author_name)
    folder_name = build_folder_name(repo_info, author_name)
    parent_dir = File.join(BASE_DIR, folder_name)
    FileUtils.mkdir_p(parent_dir)

    log "📁 フォルダ作成: #{parent_dir}"

    # git clone
    clone_result = `git clone "#{repo_info[:clone_url]}" "#{File.join(parent_dir, repo_info[:repo])}" 2>&1`
    repo_dir = File.join(parent_dir, repo_info[:repo])
    log "📥 git clone: #{clone_result.lines.last&.strip}"

    unless Dir.exist?(repo_dir)
      raise "git clone に失敗しました: #{clone_result}"
    end

    # VS Code を開く
    open_vscode(repo_dir)

    # ブラウザでGitHubページを開く
    open_browser(repo_info[:https_url])

    # アプリ起動
    app_started = start_app(repo_dir)

    { path: repo_dir, action: 'clone', app_started: app_started }
  end

  # デフォルトブランチを検出
  def detect_default_branch(path)
    result = `git -C "#{path}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`.strip
    if result.present?
      result.sub('refs/remotes/origin/', '')
    else
      # HEAD が設定されていない場合は main/master を試す
      branches = `git -C "#{path}" branch -r 2>/dev/null`.strip
      if branches.include?('origin/main')
        'main'
      elsif branches.include?('origin/master')
        'master'
      else
        'main'
      end
    end
  end

  # フォルダ名を生成
  def build_folder_name(repo_info, author_name)
    name_part = if author_name.present?
                  # 日本語名ならそのまま使う
                  "#{author_name}さん"
                else
                  repo_info[:owner]
                end

    # リポジトリ名からカテゴリを推定
    repo_lower = repo_info[:repo].downcase
    category = case repo_lower
               when /todo.?a/i then '_TodoA'
               when /todo.?b/i then '_TodoB'
               when /portfolio|ポートフォリオ/ then '_ポートフォリオ'
               when /clone|クローン/ then '_クローン'
               when /pdca/ then '_PDCA'
               else "_#{repo_info[:repo]}"
               end

    "#{name_part}#{category}"
  end

  # VS Code を開く
  def open_vscode(path)
    code_path = find_code_command
    if code_path
      system("#{code_path} \"#{path}\" &")
      log "💻 VS Code を開きました: #{path}"
    else
      log "⚠️ VS Code の `code` コマンドが見つかりません"
    end
  end

  def find_code_command
    # よくあるパスを試す
    candidates = [
      `which code 2>/dev/null`.strip,
      '/usr/local/bin/code',
      "#{ENV['HOME']}/.local/bin/code",
      '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',
    ]
    candidates.find { |c| c.present? && File.executable?(c) }
  end

  # ブラウザで開く
  def open_browser(url)
    system("open \"#{url}\" &")
    log "🌐 ブラウザで開きました: #{url}"
  end

  # アプリを起動（package.json の内容から判定）
  def start_app(path)
    pkg_path = File.join(path, 'package.json')
    gemfile_path = File.join(path, 'Gemfile')
    index_path = File.join(path, 'index.html')

    if File.exist?(pkg_path)
      start_node_app(path, pkg_path)
    elsif File.exist?(gemfile_path)
      start_rails_app(path)
    elsif File.exist?(index_path)
      system("open \"#{index_path}\" &")
      log "🌐 index.html を開きました"
      true
    else
      log "⚠️ 起動可能なアプリが見つかりませんでした"
      false
    end
  end

  def start_node_app(path, pkg_path)
    pkg = JSON.parse(File.read(pkg_path))
    scripts = pkg['scripts'] || {}
    deps = (pkg['dependencies'] || {}).merge(pkg['devDependencies'] || {})

    # npm install
    log "📦 npm install 実行中..."
    system("cd \"#{path}\" && npm install > /dev/null 2>&1")

    # 起動コマンド判定
    start_cmd = if scripts['dev'] && (deps['vite'] || deps['next'])
                  'npm run dev'
                elsif scripts['start']
                  'npm start'
                elsif scripts['dev']
                  'npm run dev'
                end

    if start_cmd
      # バックグラウンドで起動
      pid = spawn("cd \"#{path}\" && #{start_cmd}", [:out, :err] => '/tmp/review-app.log')
      Process.detach(pid)
      log "🚀 アプリ起動: #{start_cmd} (PID: #{pid})"
      true
    else
      log "⚠️ 起動スクリプトが見つかりません"
      false
    end
  rescue => e
    log "⚠️ アプリ起動失敗: #{e.message}"
    false
  end

  def start_rails_app(path)
    log "📦 bundle install 実行中..."
    system("cd \"#{path}\" && bundle install > /dev/null 2>&1")
    pid = spawn("cd \"#{path}\" && rails server", [:out, :err] => '/tmp/review-app.log')
    Process.detach(pid)
    log "🚀 Rails起動 (PID: #{pid})"
    true
  rescue => e
    log "⚠️ Rails起動失敗: #{e.message}"
    false
  end

  def log(msg)
    @logger.info(msg)
  end
end
