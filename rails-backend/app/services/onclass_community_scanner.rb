# オンクラスのメンションタブから未対応の GitHub URL を検出する（API 直叩き・Playwright 不要）
class OnclassCommunityScanner
  # https://あり・なし両方にマッチ
  GITHUB_URL_PATTERN = %r{(?:https?://)?github\.com/[^\s<>"'\)]+}

  # 対応済みと判定するフレーズ（メッセージ本文に含まれていたらスキップ）
  RESOLVED_PHRASES = [
    "お進みください",
    "進めてください",
    "問題なさそう",
    "問題ありません",
    "修正ありがとう",
    "LGTM",
    "lgtm",
    "良さそう",
    "いい感じ",
    "大丈夫です",
    "OKです",
    "okです",
    "確認しました",
    "レビュー済み",
    "マージして"
  ].freeze

  # activity/mentions はカーソルページング（1ページ約20件）。直近3ページまで遡る
  MAX_PAGES = 3

  def initialize(logger: nil)
    @logger = logger || Rails.logger
  end

  # メインエントリポイント: メンション一覧から未対応のGitHub URLを検出
  # Returns: [{ url:, author:, channel:, message:, images:, post_id: }]
  def scan
    results = []
    reviewed_urls = GithubReview.pluck(:github_url).to_set

    client = OnclassApiClient.from_service_connection(logger: @logger)
    client.sign_in!
    log("✅ オンクラスAPIログイン完了")

    mentions = fetch_mentions(client)
    log("📡 #{mentions.length}件のメンションを検出")

    mentions.each do |mention|
      chat = mention["chat"] || {}
      full_text = chat["text"].to_s
      next if full_text.strip.empty?

      urls = full_text.scan(GITHUB_URL_PATTERN).uniq
      next if urls.empty?

      images = Array(chat["chat_attachments"]).filter_map do |attachment|
        attachment["file_url"] || attachment["url"] || attachment["image_url"]
      end

      urls.each do |url|
        clean_url = normalize_github_url(url)
        next if reviewed_urls.include?(clean_url)

        # 同じメッセージ内に対応済みフレーズがあればスキップ
        if resolved_context?(full_text)
          log("  ⏭️ 対応済みスキップ: #{clean_url}")
          next
        end

        url_pos = full_text.index(url).to_i
        results << {
          url: clean_url,
          author: chat["user_name"].to_s,
          channel: chat.dig("channel", "name").to_s,
          message: full_text[([ url_pos - 200, 0 ].max)..([ url_pos + url.length + 500, full_text.length ].min)],
          images: images,
          post_id: chat["id"].presence || "mention_#{mention['id']}"
        }
        reviewed_urls << clean_url
        log("  🆕 未対応GitHub URL検出: #{clean_url}")
      end
    end

    log("📋 結果: #{results.length}件の未対応GitHub URL")
    results
  end

  private

  def log(msg)
    @logger.info(msg)
  end

  def fetch_mentions(client)
    mentions = []
    cursor = nil
    MAX_PAGES.times do
      page_mentions, cursor = client.activity_mentions(created_before: cursor)
      mentions.concat(page_mentions)
      break if page_mentions.empty? || cursor.blank?
    end
    mentions
  end

  # メッセージ本文から対応済みかどうかを判定
  def resolved_context?(text)
    RESOLVED_PHRASES.any? { |phrase| text.include?(phrase) }
  end

  def normalize_github_url(url)
    clean = url.sub(/[.,;:!?\)\]]+$/, "").strip
    # https:// がなければ付与
    clean = "https://#{clean}" unless clean.start_with?("http")
    clean
  end
end
