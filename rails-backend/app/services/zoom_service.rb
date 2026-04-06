require 'net/http'
require 'json'
require 'base64'

class ZoomService
  TOKEN_URL   = 'https://zoom.us/oauth/token'
  MEETING_URL = 'https://api.zoom.us/v2/users/me/meetings'

  def initialize(&log_callback)
    @log = log_callback || ->(_msg) {}
  end

  # Returns { zoom_url:, meeting_id:, passcode: }
  def create_meeting(title:, start_date:, start_time:, duration_minutes: 120)
    log("[Zoom API] ミーティング作成開始: #{title}")

    token = fetch_access_token
    log("[Zoom API] アクセストークン取得完了")

    # ISO 8601 形式の開始日時
    start_datetime = "#{start_date}T#{start_time}:00"

    body = {
      topic: title,
      type: 2, # Scheduled meeting
      start_time: start_datetime,
      duration: duration_minutes,
      timezone: 'Asia/Tokyo',
      settings: {
        waiting_room: true,
        join_before_host: false,
        mute_upon_entry: true,
        auto_recording: 'none',
      },
    }

    uri = URI(MEETING_URL)
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{token}"
    req['Content-Type'] = 'application/json'
    req.body = body.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    res = http.request(req)

    unless res.code.to_i == 201
      error_body = JSON.parse(res.body) rescue {}
      raise "Zoomミーティング作成失敗 (#{res.code}): #{error_body['message'] || res.body}"
    end

    data = JSON.parse(res.body)
    zoom_url   = data['join_url'].to_s
    meeting_id = data['id'].to_s
    passcode   = data['password'].to_s

    # meeting_id をフォーマット（xxx xxxx xxxx）
    formatted_id = meeting_id.gsub(/(\d{3})(\d{4})(\d{4})/, '\1 \2 \3')

    log("[Zoom API] ✅ ミーティング作成完了")
    log("[Zoom API] 招待リンク: #{zoom_url}")
    log("[Zoom API] ミーティングID: #{formatted_id}")
    log("[Zoom API] パスコード: #{passcode}")

    { zoom_url: zoom_url, meeting_id: formatted_id, passcode: passcode }
  end

  # Playwright版との互換性（既存の呼び出し元がpageを渡す場合）
  def create_meeting_with_page(page, title:, start_date:, start_time:, duration_minutes: 120)
    create_meeting(title: title, start_date: start_date, start_time: start_time, duration_minutes: duration_minutes)
  end

  private

  def log(msg)
    @log.call(msg.to_s)
  end

  def fetch_access_token
    account_id    = ENV['ZOOM_ACCOUNT_ID'].to_s
    client_id     = ENV['ZOOM_CLIENT_ID'].to_s
    client_secret = ENV['ZOOM_CLIENT_SECRET'].to_s

    raise 'ZOOM_ACCOUNT_ID が未設定です。Zoom Marketplace で Server-to-Server OAuth アプリを作成してください。' if account_id.blank?
    raise 'ZOOM_CLIENT_ID が未設定です' if client_id.blank?
    raise 'ZOOM_CLIENT_SECRET が未設定です' if client_secret.blank?

    uri = URI(TOKEN_URL)
    uri.query = URI.encode_www_form(grant_type: 'account_credentials', account_id: account_id)

    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
    req['Content-Type'] = 'application/x-www-form-urlencoded'

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    res = http.request(req)

    unless res.code.to_i == 200
      error_body = JSON.parse(res.body) rescue {}
      raise "Zoomトークン取得失敗 (#{res.code}): #{error_body['reason'] || error_body['message'] || res.body}"
    end

    data = JSON.parse(res.body)
    data['access_token']
  end
end
