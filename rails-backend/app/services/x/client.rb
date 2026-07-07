require "net/http"
require "json"
require "uri"
require "base64"

module X
  # X (Twitter) 直接 API クライアント。
  # 認証は web セッション cookie 方式（auth_token + ct0）。
  # Bearer は X web アプリの公開定数（全ユーザー共通）。
  #
  # ServiceConnection.session_data に JSON で auth_token / ct0 を保存しておく前提。
  class Client
    BEARER = "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA".freeze
    CREATE_TWEET_URL = "https://x.com/i/api/graphql/H-t2v_HvFR07ZBP9aOeKoA/CreateTweet".freeze
    CREATE_TWEET_QUERY_ID = "H-t2v_HvFR07ZBP9aOeKoA".freeze
    # 旧 v1.1 の verify_credentials.json は X が廃止して 404 になったため、
    # 現行 web アプリでも生きている badge_count を疎通確認に使う。
    VERIFY_URL = "https://x.com/i/api/2/badge_count/badge_count.json?supports_ntab_urt=1".freeze
    MEDIA_INIT_URL = "https://upload.x.com/1.1/media/upload.json".freeze

    # CreateTweet で使う features ハッシュ（DevTools キャプチャから固定）
    FEATURES = {
      premium_content_api_read_enabled: false,
      communities_web_enable_tweet_community_results_fetch: true,
      c9s_tweet_anatomy_moderator_badge_enabled: true,
      responsive_web_grok_analyze_button_fetch_trends_enabled: false,
      responsive_web_grok_analyze_post_followups_enabled: true,
      rweb_cashtags_composer_attachment_enabled: true,
      responsive_web_jetfuel_frame: true,
      responsive_web_grok_share_attachment_enabled: true,
      responsive_web_grok_annotations_enabled: true,
      responsive_web_edit_tweet_api_enabled: true,
      rweb_conversational_replies_downvote_enabled: false,
      graphql_is_translatable_rweb_tweet_is_translatable_enabled: true,
      view_counts_everywhere_api_enabled: true,
      longform_notetweets_consumption_enabled: true,
      responsive_web_twitter_article_tweet_consumption_enabled: true,
      content_disclosure_indicator_enabled: true,
      content_disclosure_ai_generated_indicator_enabled: true,
      responsive_web_grok_show_grok_translated_post: true,
      responsive_web_grok_analysis_button_from_backend: true,
      post_ctas_fetch_enabled: false,
      longform_notetweets_rich_text_read_enabled: true,
      longform_notetweets_inline_media_enabled: false,
      profile_label_improvements_pcf_label_in_post_enabled: true,
      responsive_web_profile_redirect_enabled: false,
      rweb_tipjar_consumption_enabled: false,
      verified_phone_label_enabled: false,
      articles_preview_enabled: true,
      rweb_cashtags_enabled: true,
      responsive_web_grok_community_note_auto_translation_is_enabled: true,
      responsive_web_graphql_skip_user_profile_image_extensions_enabled: false,
      freedom_of_speech_not_reach_fetch_enabled: true,
      standardized_nudges_misinfo: true,
      tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled: true,
      responsive_web_grok_image_annotation_enabled: true,
      responsive_web_grok_imagine_annotation_enabled: true,
      responsive_web_graphql_timeline_navigation_enabled: true
    }.freeze

    class AuthError < StandardError; end
    class ApiError < StandardError; end

    # session: { 'auth_token' => '...', 'ct0' => '...' } または ServiceConnection
    def initialize(session)
      session = session.session_data if session.respond_to?(:session_data)
      session = JSON.parse(session) if session.is_a?(String)
      @auth_token = session["auth_token"] || session[:auth_token]
      @ct0        = session["ct0"] || session[:ct0]
      @twid       = session["twid"] || session[:twid] # 任意（ユーザーID）
      raise AuthError, "auth_token がありません" if @auth_token.to_s.empty?
      raise AuthError, "ct0 がありません"         if @ct0.to_s.empty?
    end

    # 接続確認
    # 旧 verify_credentials.json は廃止済み（404）。badge_count は認証が通れば 200 を返し、
    # トークン切れなら 401/403 になるため疎通確認に使える。screen_name は返らない。
    # @return [Hash] { ok: true, id: '...' } / { ok: false, error: '...' }
    def verify
      res = http_get(VERIFY_URL)
      if res.is_a?(Net::HTTPSuccess)
        { ok: true, screen_name: nil, id: @twid, name: nil }
      else
        { ok: false, status: res.code, error: res.body.to_s[0, 400] }
      end
    end

    # ツイート投稿
    # @param text [String] 280 文字以内
    # @param media_ids [Array<String>] media upload 後の ID
    # @return [Hash] { tweet_id: '...', tweet_url: 'https://x.com/.../status/...' }
    def create_tweet(text, media_ids: [])
      media_entities = media_ids.map { |id| { media_id: id, tagged_users: [] } }
      variables = {
        tweet_text: text,
        media: { media_entities: media_entities, possibly_sensitive: false },
        semantic_annotation_ids: [],
        disallowed_reply_options: nil,
        semantic_annotation_options: { source: "UniversalLink" }
      }
      body = { variables: variables, features: FEATURES, queryId: CREATE_TWEET_QUERY_ID }.to_json

      res = http_post(CREATE_TWEET_URL, body, content_type: "application/json")
      raise ApiError, "CreateTweet 失敗 (HTTP #{res.code}): #{res.body.to_s[0, 600]}" unless res.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(res.body) rescue {}
      result = parsed.dig("data", "create_tweet", "tweet_results", "result") || {}
      tweet_id = result["rest_id"] || result.dig("legacy", "id_str")
      raise ApiError, "tweet_id が取得できません: #{parsed.inspect[0, 600]}" if tweet_id.to_s.empty?

      screen = result.dig("core", "user_results", "result", "legacy", "screen_name") ||
               result.dig("core", "user_results", "result", "core", "screen_name") ||
               verify[:screen_name] || "i"
      { tweet_id: tweet_id, tweet_url: "https://x.com/#{screen}/status/#{tweet_id}" }
    end

    # 画像アップロード（chunked: INIT → APPEND → FINALIZE）
    # @param io [IO/StringIO]
    # @param mime_type [String] image/jpeg, image/png 等
    # @return [String] media_id_string
    def upload_image(io, mime_type: "image/jpeg")
      bytes = io.read
      total = bytes.bytesize

      # INIT
      init_res = http_post(MEDIA_INIT_URL, URI.encode_www_form(command: "INIT", total_bytes: total, media_type: mime_type),
                           content_type: "application/x-www-form-urlencoded")
      raise ApiError, "media INIT 失敗 (HTTP #{init_res.code}): #{init_res.body[0, 400]}" unless init_res.is_a?(Net::HTTPSuccess)
      media_id = (JSON.parse(init_res.body) rescue {})["media_id_string"]
      raise ApiError, "media_id が取得できません" if media_id.to_s.empty?

      # APPEND（チャンクは 5MB 以下が安全。ここでは 1 チャンクで済む前提）
      boundary = "----X_BOUNDARY_#{SecureRandom.hex(8)}"
      append_body = build_multipart(boundary, [
        { name: "command", value: "APPEND" },
        { name: "media_id", value: media_id },
        { name: "segment_index", value: "0" },
        { name: "media", filename: "image.jpg", content_type: mime_type, value: bytes }
      ])
      append_res = http_post(MEDIA_INIT_URL, append_body, content_type: "multipart/form-data; boundary=#{boundary}")
      raise ApiError, "media APPEND 失敗 (HTTP #{append_res.code}): #{append_res.body.to_s[0, 400]}" unless append_res.is_a?(Net::HTTPSuccess) || append_res.code == "204"

      # FINALIZE
      finalize_res = http_post(MEDIA_INIT_URL, URI.encode_www_form(command: "FINALIZE", media_id: media_id),
                               content_type: "application/x-www-form-urlencoded")
      raise ApiError, "media FINALIZE 失敗 (HTTP #{finalize_res.code}): #{finalize_res.body[0, 400]}" unless finalize_res.is_a?(Net::HTTPSuccess)

      media_id
    end

    private

    def http_get(url)
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      set_headers(req)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    end

    def http_post(url, body, content_type: "application/json")
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      set_headers(req, content_type: content_type)
      req.body = body
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    end

    def set_headers(req, content_type: nil)
      req["authorization"]             = "Bearer #{BEARER}"
      req["x-csrf-token"]              = @ct0
      req["x-twitter-auth-type"]       = "OAuth2Session"
      req["x-twitter-active-user"]     = "yes"
      req["x-twitter-client-language"] = "ja"
      req["cookie"]                    = "auth_token=#{@auth_token}; ct0=#{@ct0}"
      req["user-agent"]                = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
      req["origin"]                    = "https://x.com"
      req["referer"]                   = "https://x.com/"
      req["content-type"]              = content_type if content_type
    end

    def build_multipart(boundary, parts)
      result = String.new(encoding: "ASCII-8BIT")
      parts.each do |p|
        result << "--#{boundary}\r\n".b
        if p[:filename]
          result << %Q(Content-Disposition: form-data; name="#{p[:name]}"; filename="#{p[:filename]}"\r\n).b
          result << "Content-Type: #{p[:content_type]}\r\n\r\n".b
          result << p[:value].b
          result << "\r\n".b
        else
          result << %Q(Content-Disposition: form-data; name="#{p[:name]}"\r\n\r\n).b
          result << p[:value].to_s.b
          result << "\r\n".b
        end
      end
      result << "--#{boundary}--\r\n".b
      result
    end
  end
end
