require "net/http"
require "json"

# YouTube動画の文字起こし（字幕）とタイトルを取得するサービス。
# APIキー不要。InnerTube（Androidクライアント）のplayerレスポンスから
# 字幕トラックを特定し、json3形式で取得する。
# ※ watchページの字幕URLはpotトークン必須化で空になるため、Android版を使う。
class YoutubeTranscriptService
  Error = Class.new(StandardError)

  INNERTUBE_PLAYER_URL = "https://www.youtube.com/youtubei/v1/player".freeze
  ANDROID_CLIENT = {
    clientName: "ANDROID",
    clientVersion: "20.10.38",
    androidSdkVersion: 30,
    hl: "ja"
  }.freeze
  ANDROID_USER_AGENT = "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip".freeze

  NOISE_PATTERN = /\[音楽\]|\[拍手\]|\[笑い\]|\[Music\]|\[Applause\]/.freeze

  def self.fetch(url)
    new.fetch(url)
  end

  # @return [Hash] { video_id:, title:, transcript: }
  def fetch(url)
    video_id = extract_video_id(url)
    raise Error, "YouTubeのURLから動画IDを取得できませんでした" unless video_id

    player = fetch_player_response(video_id)
    status = player.dig("playabilityStatus", "status")
    raise Error, "動画を取得できませんでした（#{status}）" unless status == "OK"

    {
      video_id: video_id,
      title: player.dig("videoDetails", "title").to_s,
      transcript: extract_transcript(player)
    }
  end

  def extract_video_id(url)
    text = url.to_s.strip
    [
      %r{youtu\.be/([\w-]{11})},
      %r{youtube\.com/(?:watch\?v=|shorts/|live/|embed/)([\w-]{11})},
      /\A([\w-]{11})\z/
    ].each do |pattern|
      matched = text.match(pattern)
      return matched[1] if matched
    end
    nil
  end

  private

  def fetch_player_response(video_id)
    uri = URI(INNERTUBE_PLAYER_URL)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["User-Agent"] = ANDROID_USER_AGENT
    request.body = {
      context: { client: ANDROID_CLIENT },
      videoId: video_id
    }.to_json

    response = http_request(uri, request)
    raise Error, "YouTube APIの呼び出しに失敗しました（HTTP #{response.code}）" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise Error, "YouTube APIレスポンスの解析に失敗しました"
  end

  def extract_transcript(player)
    caption_tracks = player.dig("captions", "playerCaptionsTracklistRenderer", "captionTracks") || []
    raise Error, "この動画には字幕（文字起こし）がありません" if caption_tracks.empty?

    track = select_preferred_track(caption_tracks)
    events = fetch_caption_events(track["baseUrl"])
    transcript = events.filter_map { |event|
      segments = event["segs"]
      next unless segments

      segments.map { |segment| segment["utf8"].to_s }.join.strip.presence
    }.join("\n")
    transcript = transcript.gsub(NOISE_PATTERN, " ").gsub(/[ \t]+/, " ").strip
    raise Error, "字幕の取得結果が空でした" if transcript.empty?

    transcript
  end

  # 日本語の手動字幕 > 日本語の自動生成字幕 > 先頭トラック の優先順で選ぶ
  def select_preferred_track(caption_tracks)
    japanese_tracks = caption_tracks.select { |track| track["languageCode"].to_s.start_with?("ja") }
    japanese_tracks.find { |track| track["kind"] != "asr" } ||
      japanese_tracks.first ||
      caption_tracks.first
  end

  def fetch_caption_events(base_url)
    raise Error, "字幕URLを取得できませんでした" if base_url.to_s.empty?

    # 既存の fmt パラメータ（srv3等）を除去して json3 で取得する
    json_url = base_url.gsub(/[&?]fmt=[^&]*/, "") + "&fmt=json3"
    uri = URI(json_url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = ANDROID_USER_AGENT

    response = http_request(uri, request)
    raise Error, "字幕の取得に失敗しました（HTTP #{response.code}）" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["events"] || []
  rescue JSON::ParserError
    raise Error, "字幕データの解析に失敗しました"
  end

  def http_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 15
    http.read_timeout = 30
    http.request(request)
  end
end
