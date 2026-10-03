require "net/http"
require "uri"
require "json"

# オンクラス管理画面 API クライアント（Playwright 不要）
#
# 2026/03 に onclass の認証が devise_token_auth から
# Cookie セッション + CSRF トークン方式へ変更された。ログインは 2 ステップ:
#   1) GET  /v1/auth/enterprise_manager/csrf_token → x-csrf-token ヘッダを取得
#   2) POST /v1/auth/enterprise_manager/session    body={session:{email,password}}
#      → Set-Cookie のセッション Cookie で以降の API を認証する
# 更新系（POST/PATCH/DELETE）は X-CSRF-Token ヘッダも必要。
class OnclassApiClient
  API_BASE       = "https://api.the-online-class.com".freeze
  MANAGER_ORIGIN = "https://manager.the-online-class.com".freeze

  CSRF_PATH    = "/v1/auth/enterprise_manager/csrf_token".freeze
  SESSION_PATH = "/v1/auth/enterprise_manager/session".freeze

  class Error < StandardError; end

  def initialize(email:, password:, logger: Rails.logger)
    @email      = email
    @password   = password
    @logger     = logger
    @cookies    = {}
    @csrf_token = nil
  end

  # ServiceConnection('onclass') の資格情報からクライアントを生成
  def self.from_service_connection(logger: Rails.logger)
    creds    = ServiceConnection.credentials_for("onclass")
    email    = creds[:email].presence
    password = creds[:password].presence
    if email.blank? || password.blank?
      raise Error, "[オンクラス] 認証情報が未設定です。接続管理からメールアドレスとパスワードを登録してください。"
    end

    new(email: email, password: password, logger: logger)
  end

  def sign_in!
    csrf_res    = request(:get, CSRF_PATH)
    @csrf_token = csrf_res["x-csrf-token"]

    res  = request(:post, SESSION_PATH, json: { session: { email: @email, password: @password } })
    body = parse_json(res)
    unless res.is_a?(Net::HTTPSuccess) && body["authenticated"]
      errors = Array(body["errors"]).join(", ")
      raise Error, "[オンクラス] ログイン失敗 (status=#{res.code}) #{errors}"
    end

    @csrf_token = res["x-csrf-token"] || @csrf_token
    @logger&.info("[OnclassApiClient] ✅ ログイン成功")
    true
  end

  def signed_in?
    @cookies.any?
  end

  # コミュニティのチャンネル一覧 [{ 'id' =>, 'name' => }]
  def channels
    fetch_data("/v1/enterprise_manager/enterprise_managers/current/channels")
  end

  # チャンネルのメンション候補 [{ 'id' =>, 'name' =>, 'mention_role' => }]
  def mention_addresses(channel_id)
    fetch_data("/v1/enterprise_manager/communities/mentions/addresses?#{URI.encode_www_form(channel_id: channel_id)}")
  end

  # 自分宛メンション一覧（新しい順・カーソルページング）
  # Returns: [mentions(Array), next_cursor(String|nil)]
  def activity_mentions(created_before: nil)
    path = "/v1/enterprise_manager/communities/activity/mentions"
    path += "?#{URI.encode_www_form(created_before: created_before)}" if created_before.present?
    body = parse_json(request_authorized(:get, path))
    [ Array(body["data"]), body.dig("meta", "next_cursor") ]
  end

  # 講座一覧 [{ 'id' =>, 'name' => }]
  def learning_courses
    fetch_data("/v1/enterprise_manager/enterprise_managers/current/learning_courses")
  end

  # 受講生一覧（learning_course_id 指定で講座絞り込み・全ページ取得）
  def users(learning_course_id: nil)
    collected   = []
    page_number = 1
    loop do
      query = { page: page_number }
      query[:learning_course_id] = learning_course_id if learning_course_id
      body = parse_json(request_authorized(:get, "/v1/enterprise_manager/users?#{URI.encode_www_form(query)}"))
      collected.concat(Array(body["data"]))
      total_pages = body.dig("meta", "pager", "total_pages").to_i
      break if page_number >= total_pages

      page_number += 1
    end
    collected
  end

  # コミュニティチャンネルへメッセージ送信（メンション・画像添付対応）
  # mention_targets: [{ id:, name:, role: }]（mentions/addresses の候補から構築する）
  # 送信は SPA と同じ multipart/form-data で、mention_targets は JSON 文字列として渡す
  def create_chat(channel_id:, text:, mention_targets: [], attachment_paths: [])
    ensure_signed_in!

    attachment_files = Array(attachment_paths).map { |path| File.open(path, "rb") }
    form = [
      [ "channel_id", channel_id.to_s ],
      [ "text", text.to_s ],
      [ "mention_targets", JSON.generate(mention_targets) ]
    ]
    attachment_files.each { |file| form << [ "attachment_files[]", file ] }

    uri = URI("#{API_BASE}/v1/enterprise_manager/communities/chats")
    req = Net::HTTP::Post.new(uri)
    apply_headers(req, with_csrf: true)
    req.set_form(form, "multipart/form-data")

    res = http_for(uri).request(req)
    merge_cookies(res)
    body = parse_json(res)
    unless res.is_a?(Net::HTTPSuccess)
      detail = body["message"] || Array(body["errors"]).join(", ")
      raise Error, "[オンクラス] メッセージ送信失敗 (status=#{res.code}) #{detail}"
    end

    body["data"]
  ensure
    attachment_files&.each { |file| file.close rescue nil }
  end

  private

  def ensure_signed_in!
    sign_in! unless signed_in?
  end

  # GET してレスポンスの data 配列を返す（認証込み）
  def fetch_data(path)
    Array(parse_json(request_authorized(:get, path))["data"])
  end

  def request_authorized(method, path, json: nil)
    ensure_signed_in!
    res = request(method, path, json: json)
    unless res.is_a?(Net::HTTPSuccess)
      body   = parse_json(res)
      detail = body["message"] || Array(body["errors"]).join(", ")
      raise Error, "[オンクラス] API失敗 #{method.upcase} #{path} (status=#{res.code}) #{detail}"
    end
    res
  end

  def request(method, path, json: nil)
    uri = URI("#{API_BASE}#{path}")
    req = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri)
    apply_headers(req, with_csrf: method != :get)
    if json
      req["content-type"] = "application/json"
      req.body = JSON.generate(json)
    end
    res = http_for(uri).request(req)
    merge_cookies(res)
    res
  end

  def http_for(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl       = true
    http.open_timeout  = 30
    http.read_timeout  = 60
    http
  end

  def apply_headers(req, with_csrf: false)
    req["accept"]       = "application/json, text/plain, */*"
    req["origin"]       = MANAGER_ORIGIN
    req["referer"]      = "#{MANAGER_ORIGIN}/"
    req["user-agent"]   = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    req["Cookie"]       = cookie_header if @cookies.any?
    req["X-CSRF-Token"] = @csrf_token if with_csrf && @csrf_token.present?
  end

  def cookie_header
    @cookies.map { |name, value| "#{name}=#{value}" }.join("; ")
  end

  def merge_cookies(res)
    Array(res.get_fields("set-cookie")).each do |set_cookie|
      pair = set_cookie.split(";").first.to_s.strip
      name, value = pair.split("=", 2)
      @cookies[name] = value if name.present? && value.present?
    end
  end

  def parse_json(res)
    JSON.parse(res.body.to_s)
  rescue JSON::ParserError
    {}
  end
end
