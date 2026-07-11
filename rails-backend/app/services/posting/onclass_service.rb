module Posting
  # オンクラス コミュニティ投稿（API 直叩き・Playwright 不要）
  #
  # 2026/06 のオンクラス改修でログインが 2 段階化され Playwright の DOM 操作が全滅したため、
  # SPA が使う API（OnclassApiClient 参照）へ移行した。
  # メンションは text への「@名前」埋め込みではなく mention_targets パラメータで確定するため、
  # オートコンプリート操作起因の「メンションされない」バグは構造的に起きない。
  class OnclassService < BaseService
    # TestConnectionJob からも呼ばれる。API ベースなので page は使わない。
    def ensure_login(_page = nil)
      client.sign_in!
      log("[オンクラス] ✅ APIログイン成功")
    end

    private

    def client
      @client ||= OnclassApiClient.from_service_connection(logger: Rails.logger)
    end

    def execute(_page, content, ef)
      channel_names = parse_channels(ef)
      raise "[オンクラス] チャンネルが選択されていません" if channel_names.empty?

      image_path = ef["onclassImagePath"].presence || ef["imagePath"].presence
      attachment_paths = image_path.present? && File.exist?(image_path.to_s) ? [ image_path.to_s ] : []

      ensure_login

      # メンション対象: UIから渡された場合はそれを使用、なければDB同期済みのフロントコース受講生
      mention_names = parse_mentions(ef)
      mention_names = fallback_mention_names if mention_names.empty?
      log("[オンクラス] メンション対象: #{mention_names.length}名")

      all_channels = client.channels

      # オンクラス（受講生コミュニティ）はMarkdownを解釈しないため、主催者プロフィール
      # ブロック（マーケ用・生Markdown）は投稿しない。本文はユーザーが書いたものだけにする。
      body = strip_auto_blocks(content)

      channel_names.each do |channel_name|
        channel = find_channel(all_channels, channel_name)
        targets = resolve_mention_targets(channel["id"], mention_names)
        log("[オンクラス] チャンネル「#{channel['name']}」にメッセージ送信中...（メンション#{targets.length}名）")
        client.create_chat(
          channel_id:       channel["id"],
          text:             compose_text(body, targets),
          mention_targets:  targets,
          attachment_paths: attachment_paths,
        )
        log("[オンクラス] ✅ チャンネル「#{channel['name']}」送信完了")
      end

      log("[オンクラス] ✅ 全#{channel_names.length}チャンネルへの送信完了")
    end

    def find_channel(all_channels, channel_name)
      wanted = normalize_name(channel_name)
      channel = all_channels.find { |c| normalize_name(c["name"]) == wanted }
      channel ||= all_channels.find do |c|
        name = normalize_name(c["name"])
        name.include?(wanted) || wanted.include?(name)
      end

      unless channel
        log("[オンクラス] 利用可能チャンネル: #{all_channels.map { |c| c['name'] }.join(' / ')}")
        raise "[オンクラス] チャンネル「#{channel_name}」が見つかりません"
      end
      channel
    end

    # チャンネルのメンション候補と名前を突き合わせて mention_targets を構築する。
    # 名前は全角/半角スペースの揺れがあるため空白を除去して比較する。
    def resolve_mention_targets(channel_id, mention_names)
      return [] if mention_names.empty?

      addresses = client.mention_addresses(channel_id)
      address_by_name = addresses.index_by { |a| normalize_name(a["name"]) }

      mention_names.filter_map do |name|
        address = address_by_name[normalize_name(name)]
        unless address
          log("[オンクラス] ⚠️ メンション候補なし: #{name}")
          next
        end
        { id: address["id"], name: address["name"], role: address["mention_role"] }
      end
    end

    def compose_text(content, targets)
      return content if targets.empty?

      mention_line = targets.map { |t| "@#{t[:name]}" }.join(" ")
      "#{mention_line} \n#{content}"
    end

    # 自動生成された主催者プロフィールブロック（マーカーで囲まれた生Markdown）を除去する。
    # 過去の自動追記で本文に焼き込まれた分も含め、オンクラスには出さない。
    def strip_auto_blocks(content)
      content.to_s
             .gsub(/\n*<!-- HOST-PROFILE-START -->.*?<!-- HOST-PROFILE-END -->\n*/m, "\n")
             .strip
    end

    def fallback_mention_names
      OnclassStudent.active_frontend.order(:name).pluck(:name)
    rescue StandardError
      []
    end

    def normalize_name(name)
      name.to_s.gsub(/[[:space:]]+/, "")
    end

    def parse_mentions(ef)
      raw = ef["onclassMentions"]
      case raw
      when Array then raw.select { |n| n.is_a?(String) && n.present? }
      else []
      end
    end

    def parse_channels(ef)
      raw = ef["onclassChannels"]
      case raw
      when Array then raw
      when String then raw.split(",").map(&:strip).reject(&:empty?)
      else [ "全体チャンネル" ]
      end
    end

    def perform_delete(_page, _event_url)
      log("[オンクラス] 削除操作は未対応です")
    end

    def perform_cancel(_page, _event_url)
      log("[オンクラス] 中止操作は未対応です")
    end
  end
end
