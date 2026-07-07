require 'net/http'
require 'json'

module X
  # 投稿済みイベントに対して、イベント日時の前 4 タイミングで X 告知ツイートを XPost に作成する。
  # 1) 1 週間前  (19:00)
  # 2) 3 日前    (12:00)
  # 3) 当日朝   (08:00)
  # 4) 開催 10 分前
  #
  # 4 種類の本文は OpenAI に 1 リクエストで生成依頼（タイミング毎にトーン違い）し、
  # 各文末に申込 URL（Peatix 優先）を付ける。
  class EventAnnouncer
    OPENAI_URL = 'https://api.openai.com/v1/chat/completions'.freeze
    MODEL      = 'gpt-4o-mini'.freeze

    OFFSETS = [
      { label: '1week_before', anchor: :date, days: -7, hour: 19, minute: 0 },
      { label: '3days_before', anchor: :date, days: -3, hour: 12, minute: 0 },
      { label: 'same_day',     anchor: :date, days:  0, hour:  8, minute: 0 },
      { label: '10min_before', anchor: :event_at, minutes: -10 },
    ].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      X (Twitter) でイベント告知ツイートを 4 種類書きます。同じイベントについて、4 つの異なるタイミング (1週間前 / 3日前 / 当日朝 / 10分前) に流す告知用です。

      ## トーン要件
      - AI っぽさ・営業臭・自己啓発っぽさを徹底排除
      - 「みなさん」「ぜひ」「いかがでしたか」「〜と言われています」禁止
      - 語尾をバラけさせる。「〜よ」「〜だった」「〜してる」「〜って思う」「〜かな」等
      - 体言止め、半疑問、独り言混ぜる
      - 絵文字は 0〜1 個 / ツイート、連発しない
      - ハッシュタグは付けるなら 1 個

      ## タイミング別ニュアンス
      - **1week_before**: 「来週」「あと1週間」のような期待を煽る感じ。本人がワクワクしてる風
      - **3days_before**: あと数日。具体的にどんな話するかチラ見せ
      - **same_day**: 今日です感。当日の天気とか自分の気分も少し交えて自然に
      - **10min_before**: もうすぐ始まる。最後の駆け込み案内

      ## 形式
      - 各ツイート 130〜220 文字
      - 申込 URL は **入れない**（呼び出し側で末尾に追加するので）
      - 出力は JSON 配列 1 つ。キーは `1week_before` `3days_before` `same_day` `10min_before`
        例: {"1week_before":"...","3days_before":"...","same_day":"...","10min_before":"..."}
      - 説明文・前置きは一切付けない
    PROMPT

    # 生成と XPost 作成を一括実行
    # @return [Array<XPost>] 作成された XPost の配列（過去日のものはスキップ）
    def self.generate_and_save(user:, item_id:, title:, event_date:, event_time:, signup_url:)
      new.generate_and_save(user: user, item_id: item_id, title: title, event_date: event_date, event_time: event_time, signup_url: signup_url)
    end

    # PostingHistory から申込 URL を Peatix 優先で 1 つ拾う
    SITE_PRIORITY = %w[Peatix Doorkeeper こくチーズ connpass TechPlay つなゲート EventRegist セミナーBiZ ストアカ Luma BIZee ジモティー].freeze
    def self.pick_signup_url(item_id)
      base = PostingHistory.where(item_id: item_id, status: 'success', published: true).where.not(event_url: [nil, ''])
      SITE_PRIORITY.each do |site|
        url = base.where(site_name: site).order(posted_at: :desc).first&.event_url
        return url if url.present?
      end
      base.order(posted_at: :desc).first&.event_url
    end

    def generate_and_save(user:, item_id:, title:, event_date:, event_time:, signup_url:)
      event_at = combine_datetime(event_date, event_time)
      return [] if event_at.nil?

      key = ENV['OPENAI_API_KEY'].to_s.presence || AppSetting.get('openai_api_key').to_s.presence
      return [] if key.to_s.empty?

      variants = call_openai(key, title: title, event_date: event_date, event_time: event_time)
      now = Time.current

      OFFSETS.map do |o|
        text = variants[o[:label]].to_s.strip
        next nil if text.empty?

        scheduled = compute_scheduled_at(event_at, event_date, o)
        next nil if scheduled.nil? || scheduled < now

        body = signup_url.present? ? "#{text}\n\n📌 申込はこちら\n#{signup_url}" : text
        body = body[0, 270] + '…' if body.length > 280
        user.x_posts.create!(content: body, scheduled_at: scheduled, source: 'from_event', item_id: item_id)
      end.compact
    rescue => e
      Rails.logger.warn("[X::EventAnnouncer] generate_and_save failed: #{e.class}: #{e.message}")
      []
    end

    private

    def combine_datetime(event_date, event_time)
      return nil if event_date.blank?
      date = Date.parse(event_date.to_s)
      time = event_time.to_s.match?(/\A\d{1,2}:\d{2}/) ? event_time.to_s : '10:00'
      hour, minute = time.split(':').map(&:to_i)
      Time.zone.local(date.year, date.month, date.day, hour, minute, 0)
    rescue StandardError
      nil
    end

    def compute_scheduled_at(event_at, event_date, offset)
      if offset[:anchor] == :event_at
        event_at + (offset[:minutes] || 0).minutes
      else
        date = Date.parse(event_date.to_s) + (offset[:days] || 0).days
        Time.zone.local(date.year, date.month, date.day, offset[:hour] || 9, offset[:minute] || 0, 0)
      end
    rescue StandardError
      nil
    end

    def call_openai(key, title:, event_date:, event_time:)
      user_prompt = <<~U
        イベント情報:
        - タイトル: #{title}
        - 開催日: #{event_date}
        - 開始時刻: #{event_time}

        上記イベントについて、4 タイミング分のツイートを JSON で返してください。
      U
      body = {
        model: MODEL,
        temperature: 0.9,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user',   content: user_prompt },
        ],
      }.to_json
      uri = URI(OPENAI_URL)
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{key}"
      req['Content-Type']  = 'application/json'
      req.body = body
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) { |h| h.request(req) }
      raise "OpenAI #{res.code}: #{res.body.to_s[0,300]}" unless res.is_a?(Net::HTTPSuccess)
      content = JSON.parse(res.body).dig('choices', 0, 'message', 'content').to_s
      JSON.parse(content)
    rescue StandardError => e
      Rails.logger.warn("[X::EventAnnouncer] OpenAI failed: #{e.message}")
      {}
    end
  end
end
