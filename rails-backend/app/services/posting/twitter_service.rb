module Posting
  # X (Twitter) 投稿サービス。
  # 旧: Playwright で x.com/i/flow/login → 投稿欄をクリック
  # 新: ServiceConnection.session_data の auth_token + ct0 で X::Client 直接 API
  #
  # post_job.rb から ef['publishSites']['X'] が true のときに呼ばれる。
  # SNS なので「公開希望なし」のパターンはなく、選ばれたら即投稿。
  class TwitterService < BaseService
    private

    def execute(_page, content, ef)
      conn = ServiceConnection.find_by(service_name: 'x')
      raise '[X] 接続未登録です。設定 → X 接続から auth_token / ct0 を登録してください。' if conn.nil? || conn.session_data.blank?

      title     = extract_title(ef, content, 60)
      event_url = find_event_url(ef)
      text      = build_tweet(title, content, event_url, ef)

      log("[X] ツイート投稿中...")
      log("[X] 本文: #{text[0, 100]}...")

      client = X::Client.new(conn.session_data)

      media_ids = []
      if ef['imagePath'].present?
        io, mime = open_local_image(ef['imagePath'])
        media_ids << client.upload_image(io, mime_type: mime) if io
      end

      result = client.create_tweet(text, media_ids: media_ids)
      log("[X] ✅ ツイート完了 → #{result[:tweet_url]}")
      @published = true
      result[:tweet_url]
    end

    def build_tweet(title, content, event_url, ef)
      date_str = ef['startDate'].present? ? "#{ef['startDate']} #{ef['startTime']}" : ''
      lines = []
      lines << title
      lines << ''
      lines << "📅 #{date_str}" if date_str.present?
      lines << '💻 オンライン開催' if ef['place']&.include?('オンライン')
      lines << ''
      lines << '#プログラミング #エンジニア'
      if event_url.present?
        lines << ''
        lines << '📌 お申し込みはこちら'
        lines << event_url
      end

      tweet = lines.join("\n")
      tweet.length > 270 ? tweet[0, 267] + '...' : tweet
    end

    def find_event_url(ef)
      return ef['eventUrl'] if ef['eventUrl'].present?
      item_id = ef['itemId'].presence
      return nil unless item_id
      history = PostingHistory.where(item_id: item_id, status: 'success')
        .where.not(event_url: [nil, '', 'about:blank'])
        .order(posted_at: :desc).first
      history&.event_url
    end

    def open_local_image(path)
      full = path.start_with?('/') ? path : Rails.root.join(path).to_s
      return [nil, nil] unless File.exist?(full)
      mime = case File.extname(full).downcase
             when '.png'  then 'image/png'
             when '.gif'  then 'image/gif'
             when '.webp' then 'image/webp'
             else 'image/jpeg'
             end
      [File.open(full, 'rb'), mime]
    end

    # --- 削除・中止 ---

    def perform_delete(_page, _event_url)
      log('[X] ツイート削除は X 管理画面から手動で行ってください')
    end

    def perform_cancel(page, event_url)
      perform_delete(page, event_url)
    end
  end
end
