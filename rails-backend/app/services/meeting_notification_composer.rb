require "net/http"
require "json"

# ミーティング通知の本文を組み立てる。
#
# Zoom URL / ミーティングID / パスコードは AI に触らせず、コード側で固定ブロックとして
# 埋め込む（AI が書き換えると誤ったリンクを配信してしまうため）。AI が生成するのは
# 冒頭の短い挨拶だけで、毎回わずかに文面を変えて「テンプレ感」を薄める。
# API キー未設定・API 失敗時は固定の挨拶にフォールバックし、通知が止まらないようにする。
class MeetingNotificationComposer
  OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
  MODEL      = "gpt-4o-mini".freeze
  DEFAULT_GREETING = "お疲れ様です！".freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    あなたはプログラミングスクールの講師です。受講生チームの定例ミーティング開始前に、
    コミュニティへ送る「短い挨拶の一言」だけを書きます。

    条件:
    - 1〜2行、最大60文字程度。丁寧だが硬すぎない口語
    - 「お疲れ様です」系の挨拶から始める
    - URL・日時・パスコードは書かない（後ろにシステムが付ける）
    - 絵文字は多くても1個。ビックリマークの連発はしない
    - 毎回わずかに言い回しを変える
    出力は挨拶文そのものだけ（前置き・引用符・説明は不要）。
  PROMPT

  def initialize(config, date: nil)
    @config = config
    @date   = date || MeetingNotification::ZONE.today
  end

  def call
    template = @config.message_template.presence || MeetingNotification::DEFAULT_TEMPLATE
    render(drop_blank_lines(template))
  end

  private

  # meeting_id / passcode が空なら、その値を差し込む行ごと削除する
  # （「ミーティング ID: 」のような空行を残さないため）
  def drop_blank_lines(template)
    lines = template.lines
    lines = lines.reject { |line| line.include?("{meeting_id}") } if @config.meeting_id.blank?
    lines = lines.reject { |line| line.include?("{passcode}") } if @config.passcode.blank?
    lines.join
  end

  # プレースホルダを実値へ置換する。{greeting} が含まれる場合のみ AI 挨拶を生成する。
  def render(template)
    substitutions = {
      "{date}"       => @config.meeting_date_label(@date),
      "{time}"       => @config.meeting_time_label,
      "{zoom_url}"   => @config.zoom_url.to_s,
      "{meeting_id}" => @config.formatted_meeting_id,
      "{passcode}"   => @config.passcode.to_s,
      "{name}"       => @config.name.to_s
    }
    substitutions["{greeting}"] = (generate_greeting.presence || DEFAULT_GREETING) if template.include?("{greeting}")

    substitutions.reduce(template) { |text, (key, value)| text.gsub(key, value) }.strip
  end

  def generate_greeting
    key = openai_api_key
    return nil if key.blank?

    body = {
      model: MODEL,
      temperature: 0.9,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user",   content: "#{@config.name} の定例ミーティング通知の挨拶を1つ。" }
      ]
    }.to_json

    uri = URI(OPENAI_URL)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{key}"
    req["Content-Type"]  = "application/json"
    req.body = body
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) { |h| h.request(req) }
    return nil unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).dig("choices", 0, "message", "content").to_s.strip.delete('"')
  rescue StandardError => e
    Rails.logger.warn("[MeetingNotificationComposer] 挨拶生成失敗、既定文にフォールバック: #{e.message}")
    nil
  end

  def openai_api_key
    ENV["OPENAI_API_KEY"].to_s.presence || (AppSetting.get("openai_api_key").to_s.presence rescue nil)
  end
end
