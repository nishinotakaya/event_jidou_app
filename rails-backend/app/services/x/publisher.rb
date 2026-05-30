require 'net/http'
require 'uri'
require 'stringio'

module X
  # XPost を 1 件 X に投稿する共通ロジック。
  # 毎分の cron バッチ (XPostScheduledJob) と、手動の即時投稿 (XController#post_now)
  # の両方から呼ばれる。投稿に成功すれば XPost を posted に、失敗すれば failed に更新し、
  # 呼び出し側へ結果 (Result) を返す。例外は内部で握って Result に変換するので、
  # 呼び出し側は ok? を見るだけでよい。
  class Publisher
    Result = Struct.new(:ok, :error, :tweet_url, :needs_reconnect, keyword_init: true) do
      def ok? = ok
    end

    NOT_CONNECTED = 'not_connected'.freeze

    # X の認証/セッション切れを示すシグネチャ。これらが出たら接続を error に落として再接続を促す。
    # code 353 = "This request requires a matching csrf cookie"（ct0 期限切れ/不一致）
    AUTH_ERROR_SIGNATURES = ['HTTP 401', 'HTTP 403', '"code":353', 'csrf', 'Could not authenticate'].freeze

    def initialize(post)
      @post = post
    end

    # @return [Result]
    def call
      @conn = ServiceConnection.find_by(user_id: @post.user_id, service_name: 'x')
      if @conn.nil? || @conn.session_data.blank?
        message = 'X が未接続です。接続設定で auth_token / ct0 を登録してください'
        @post.mark_failed!(message)
        return Result.new(ok: false, error: message, needs_reconnect: true)
      end

      client = X::Client.new(@conn.session_data)
      media_ids = build_media_ids(client)
      result = client.create_tweet(@post.content, media_ids: media_ids)

      @post.mark_posted!(tweet_id: result[:tweet_id], tweet_url: result[:tweet_url])
      @conn.update(status: 'connected', last_connected_at: Time.current, error_message: nil)
      Result.new(ok: true, tweet_url: result[:tweet_url])
    rescue => e
      raw = "#{e.class}: #{e.message}"
      auth = auth_error?(raw)
      @post.mark_failed!(raw)
      # 認証切れ（ct0 期限切れ等）なら接続を error に落とし、UI に「再接続が必要」を出させる。
      @conn&.update(status: 'error', error_message: raw[0, 500]) if auth
      Rails.logger.error("[X::Publisher] post=#{@post.id} #{raw}\n#{e.backtrace&.first(5)&.join("\n")}")
      message = auth ? 'X のセッションが切れています。接続設定で auth_token / ct0 を取り直してください（CSRF/認証エラー）' : raw
      Result.new(ok: false, error: message, needs_reconnect: auth)
    end

    private

    def auth_error?(message)
      msg = message.to_s
      AUTH_ERROR_SIGNATURES.any? { |sig| msg.include?(sig) }
    end

    def build_media_ids(client)
      return [] if @post.image_url.blank?

      io, mime = fetch_image(@post.image_url)
      return [] unless io

      [client.upload_image(io, mime_type: mime)]
    end

    # Cloudinary 等の URL またはローカルパスから IO を取得
    def fetch_image(url_or_path)
      if url_or_path.start_with?('http://', 'https://')
        uri = URI(url_or_path)
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |h| h.request(Net::HTTP::Get.new(uri)) }
        return [nil, nil] unless res.is_a?(Net::HTTPSuccess)

        [StringIO.new(res.body), res['content-type'] || 'image/jpeg']
      else
        path = Rails.root.join(url_or_path).to_s
        return [nil, nil] unless File.exist?(path)

        [File.open(path, 'rb'), mime_from_ext(File.extname(path))]
      end
    end

    def mime_from_ext(ext)
      case ext.downcase
      when '.png'  then 'image/png'
      when '.gif'  then 'image/gif'
      when '.webp' then 'image/webp'
      else              'image/jpeg'
      end
    end
  end
end
