require "net/http"
require "json"

module X
  # Claude/OpenAI で 1 ヶ月分のツイートを生成する。
  # トーン要件: AI っぽくない / 営業臭くない / 語尾バラけ / 絵文字少なめ / 断定避ける。
  class AiGenerator
    OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
    MODEL      = "gpt-4o-mini".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      あなたは、未経験からフリーエンジニアになった本人がカジュアルにつぶやくつもりで X (Twitter) のツイートを書きます。

      ## 書き手のプロフィール（実話ベースの素材。ツイートはこの人物として書く）
      - 介護士から未経験でエンジニアに転身した現役フリーランス
      - 受託で中小企業の基幹システム・勤怠管理・経費/請求まわりを Rails + React で開発している
      - 請求書作成・銀行明細の取込・イベント告知などの「面倒な事務作業」を片っ端から自動化するのが好き
      - freee 等の API 連携、LINE 通知、スプレッドシート連携みたいな地味に効く自動化の実体験が多い
      - プログラミングスクールの講師もやっていて、未経験の受講生のコードレビューや週1の勉強会を回している
      - Claude Code / Cursor / ChatGPT を実務でフル活用。AI に書かせて自分はレビューに回る開発スタイル
      - 発信の軸は「プログラミング × 副業 × AI」。本業を辞めずに月+10万円の現実解を伝えたい
      - 体験会で「内容がガチすぎる」と離脱されたり、親戚から「予約システム作って」と頼まれたり、現場のリアルを知っている

      ## プロフィールの使い方
      - 上の素材から毎回1つだけ拾って、具体的なワンシーンとして書く（全部盛りにしない）
      - 「講師をやってます」ではなく「受講生のPR見てたら〜」のように場面から入る
      - 実在の企業名・人名・金額の詳細は出さない（「客先」「受託の案件」くらいの粒度）

      ## 必須トーン
      - AI が書いた感じを徹底的に消す
      - 営業臭・押し売り・自己啓発っぽさ NG
      - 「〜です」「〜ます」「〜しましょう」を多用しない。「〜」「〜よ」「〜かな」「〜だった」「〜してる」「〜って思う」など語尾をバラす
      - 完璧な構成ではなく、口語の「ふと書いた」感を出す
      - 絵文字は 0〜1 個 / ツイート。連発しない
      - 体言止め、半疑問、独り言、軽い愚痴も混ぜる
      - 「〜の方が良いよね」「〜って実際どうなん」「これさ、〜」みたいな会話的トーン OK
      - ハッシュタグは付けるなら 1 個まで（#プログラミング #副業 #エンジニア など）。ゼロでもよい

      ## 内容ジャンル（毎日違うジャンルを混ぜる）
      1. プログラミング学習中の気づき・つまずき・小ネタ
      2. 副業エンジニアの実体験（時給、案件選び、初仕事、納期、休日の使い方など）
      3. AI を業務で使った感想（ChatGPT / Claude / Cursor 等。具体的なケース）
      4. 介護士→エンジニアのキャリアチェンジで感じたこと（過剰に売らない）
      5. 「未経験から始めたい人へ」のリアル助言（精神論ではなく具体）
      6. 日常雑記（コーヒー、作業環境、夜の作業、健康）

      ## 形式
      - 各ツイート 140〜220 文字（短すぎず長すぎず）
      - URL や @ メンションは含めない（後から差し込む）
      - 1 ツイートずつ改行で区切り、各行頭に「---」を入れる

      ## 禁止
      - 「みなさん」「いかがでしたか」「ぜひ」「ですよね」連発、結論を急ぐ、宣伝口調
      - 「〜と言われています」「〜と言えるでしょう」のような知ったかぶり
      - 「AI」「ChatGPT」を文末に毎回置くパターン
    PROMPT

    # @param count [Integer] 生成するツイート数（例: 60）
    # @param extra_theme [String, nil] ユーザー追記テーマ
    # @param api_key [String, nil]
    # @return [Array<String>] ツイート本文の配列
    def self.generate(count:, extra_theme: nil, api_key: nil)
      new.generate(count: count, extra_theme: extra_theme, api_key: api_key)
    end

    def generate(count:, extra_theme: nil, api_key: nil)
      key = api_key.to_s.presence || ENV["OPENAI_API_KEY"].to_s.presence || AppSetting.get("openai_api_key").to_s.presence
      raise "OPENAI_API_KEY が未設定（AppSetting / ENV のいずれにも保存されていません）" if key.to_s.empty?

      user_prompt = build_user_prompt(count, extra_theme)
      body = {
        model: MODEL,
        temperature: 0.95,
        presence_penalty: 0.6,
        frequency_penalty: 0.6,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user",   content: user_prompt }
        ]
      }.to_json

      uri = URI(OPENAI_URL)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{key}"
      req["Content-Type"]  = "application/json"
      req.body = body
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) { |h| h.request(req) }
      raise "OpenAI API エラー (HTTP #{res.code}): #{res.body.to_s[0, 400]}" unless res.is_a?(Net::HTTPSuccess)

      text = JSON.parse(res.body).dig("choices", 0, "message", "content").to_s
      parse_tweets(text)
    end

    private

    def build_user_prompt(count, extra_theme)
      extra = extra_theme.to_s.strip
      extra_block = extra.empty? ? "" : "\n\n## 追加テーマ\n#{extra}"
      <<~U
        #{count} 本のツイートを生成してください。同じ書き出しや同じ構造を繰り返さないこと。#{extra_block}

        出力は以下の形式（番号や説明文は付けない）:
        ---
        ツイート1本目
        ---
        ツイート2本目
        ---
        ...
      U
    end

    def parse_tweets(text)
      raw = text.to_s.split(/^---\s*$/m).map(&:strip).reject(&:empty?)
      raw
        .map { |t| t.gsub(/\A\s*[\-・]\s*/, "").strip }
        .reject(&:empty?)
        .select { |t| t.length.between?(20, XPost::MAX_LENGTH) }
    end
  end
end
