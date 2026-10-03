require "net/http"
require "json"

module Api
  class AiController < ApplicationController
    OPENAI_API_URL = "https://api.openai.com/v1/chat/completions".freeze
    YOUTUBE_URL_PATTERN = %r{https?://(?:www\.|m\.)?(?:youtube\.com|youtu\.be)/\S+}.freeze

    def correct
      key  = params[:apiKey].to_s.presence || ENV["OPENAI_API_KEY"].to_s.presence || AppSetting.get("openai_api_key").to_s.presence
      text = params[:text]
      instruction = params[:instruction].to_s.presence
      return render json: { error: "OpenAI APIキーを入力してください" }, status: :bad_request unless key
      return render json: { error: "テキストを入力してください" }, status: :bad_request unless text&.strip&.present?

      system_prompt = instruction || "あなたは文章添削のプロです。入力されたテキストを、誤字脱字の修正・表現の改善・読みやすさの向上を行い、改善版を返してください。元の意図やトーンは保ちつつ、より伝わりやすい文章にしてください。改善版のみを返し、説明は不要です。"
      result = call_openai(key,
        system: system_prompt,
        user: text,
        temperature: 0.3
      )
      render json: { corrected: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def generate
      key            = params[:apiKey].presence || ENV["OPENAI_API_KEY"]
      title          = params[:title]
      type           = params[:type]
      event_date     = params[:eventDate]
      event_time     = params[:eventTime]     || "10:00"
      event_end_time = params[:eventEndTime]  || "12:00"
      event_sub_type = params[:eventSubType].presence
      zoom_url       = params[:zoomUrl].presence
      meeting_id     = params[:meetingId].presence
      passcode       = params[:passcode].presence

      return render json: { error: "OpenAI APIキーを入力してください" }, status: :bad_request unless key
      return render json: { error: "名前（タイトル）を入力してください" }, status: :bad_request unless title&.strip&.present?
      return render json: { error: "開催日時の日付を入力してください" }, status: :bad_request unless event_date&.strip&.present?

      date_str = format_date(event_date, event_time, event_end_time)
      is_event = type != "student"

      system_prompt, user_prompt = build_generate_prompts(title, is_event, event_sub_type, date_str, zoom_url, meeting_id, passcode)

      result = call_openai(key, system: system_prompt, user: user_prompt, temperature: 0.7)

      # Zoom情報は投稿時にPostModalで自動反映するため、生成時には置換しない

      result = append_host_profile(result) if is_event

      render json: { content: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def align_datetime
      key           = params[:apiKey].presence || ENV["OPENAI_API_KEY"]
      text          = params[:text]
      event_date    = params[:eventDate]
      event_time    = params[:eventTime]    || "10:00"
      event_end_time = params[:eventEndTime] || "12:00"

      return render json: { error: "OpenAI APIキーを入力してください" }, status: :bad_request unless key
      return render json: { content: text } unless text&.strip&.present? && event_date

      date_str = format_date(event_date, event_time, event_end_time)
      result = call_openai(key,
        system: "あなたはテキスト編集のアシスタントです。文章中に記載されている開催日時・日付・時刻の部分のみを、指定された日時に差し替えてください。文章の他の部分は一切変更しないでください。修正後のテキスト全体のみを返してください。",
        user: "開催日時を「#{date_str}」に合わせてください。\n\n#{text}",
        temperature: 0.1
      )
      render json: { content: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def agent
      key    = params[:apiKey].presence || ENV["OPENAI_API_KEY"]
      text   = params[:text]
      prompt = params[:prompt]

      return render json: { error: "OpenAI APIキーを入力してください" }, status: :bad_request unless key
      return render json: { error: "指示を入力してください" }, status: :bad_request unless prompt&.strip&.present?

      # 指示にYouTube URLが含まれていたら、文字起こしを取得して動画告知文を生成する
      youtube_url = prompt[YOUTUBE_URL_PATTERN]
      if youtube_url
        video = YoutubeTranscriptService.fetch(youtube_url)
        extra_instruction = prompt.sub(youtube_url, " ").strip.presence
        result = generate_youtube_announcement(key, video, extra_instruction)
        return render json: { result: result }
      end

      result = call_openai(key,
        system: "あなたは文章作成のアシスタントです。ユーザーの現在のテキストに対して、ユーザーの指示に従って修正・改善した結果を返してください。結果のテキストのみを返し、余分な説明は不要です。",
        user: "【現在のテキスト】\n#{text.presence || '(空)'}\n\n【指示】\n#{prompt}",
        temperature: 0.5
      )
      render json: { result: result }
    rescue YoutubeTranscriptService::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    # POST /api/ai/youtube-announce
    # YouTube URLから文字起こしを取得し、LME（LINE）向けの動画告知文を生成する
    def youtube_announce
      key = params[:apiKey].to_s.presence || ENV["OPENAI_API_KEY"].to_s.presence || AppSetting.get("openai_api_key").to_s.presence
      url = params[:url].to_s.presence || params[:text].to_s[YOUTUBE_URL_PATTERN]

      return render json: { error: "OpenAI APIキーを入力してください" }, status: :bad_request unless key
      return render json: { error: "YouTubeのURLを入力してください" }, status: :bad_request unless url

      video = YoutubeTranscriptService.fetch(url)
      content = generate_youtube_announcement(key, video, params[:instruction].to_s.presence)
      render json: { content: content, title: video[:title], videoUrl: "https://youtu.be/#{video[:video_id]}" }
    rescue YoutubeTranscriptService::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    # POST /api/ai/profile
    # mode='generate' → タイトル/参加対象から主催者プロフィールを新規生成
    # mode='correct'  → 既存プロフィールを「来たくなる」訴求に添削
    def profile
      key  = params[:apiKey].presence || ENV["OPENAI_API_KEY"]
      text = params[:text].to_s
      mode = params[:mode].presence || "generate"
      hint = params[:hint].to_s # 主催者の専門/経歴ヒント（任意）

      return render json: { error: "OpenAI APIキーを入力してください" }, status: :bad_request unless key

      base_system = <<~SYS.strip
        あなたはイベント主催者プロフィールを書くプロのコピーライターです。
        読者が「このイベントに参加したら、こういう未来が見える」と感じる訴求を最重視してください。

        【書き方ルール】
        - 200〜300字。誇張せず、温度感のある語り口で。
        - 一人称は柔らかく（私 / わたし）。
        - 構成は (1) 自己紹介の一文、(2) 提供できる価値・なぜそれを語れるか、(3) 参加すると得られる未来体験 の3層。
        - 絵文字は1〜2個まで控えめに。
        - 改行は読みやすさ優先で、長文の塊にしない。
        - プロフィールの本文のみを返し、見出しや前置きは不要。
      SYS

      if mode == "correct"
        return render json: { error: "プロフィール本文を入力してください" }, status: :bad_request if text.strip.empty?
        result = call_openai(key,
          system: base_system + "\n\n以下の既存プロフィールを、上記ルールに沿って『参加したくなる』訴求に磨き上げてください。",
          user: text,
          temperature: 0.5
        )
      else
        user_prompt = "ヒント（任意）：#{hint.presence || '指定なし。汎用のイベント主催者として書いてください。'}"
        result = call_openai(key, system: base_system, user: user_prompt, temperature: 0.7)
      end
      render json: { content: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    private

    def call_openai(api_key, system:, user:, temperature: 0.5)
      uri  = URI(OPENAI_API_URL)
      req  = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"]  = "application/json"
      req.body = {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: system },
          { role: "user",   content: user }
        ],
        temperature: temperature
      }.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      res  = http.request(req)
      data = JSON.parse(res.body)
      raise data.dig("error", "message") || "OpenAI APIエラー" unless res.is_a?(Net::HTTPSuccess)

      data.dig("choices", 0, "message", "content")&.strip || ""
    end

    def append_host_profile(content)
      text         = AppSetting.get("host_profile_text").to_s.strip
      youtube_url  = AppSetting.get("host_profile_youtube_url").to_s.strip
      return content if text.empty? && youtube_url.empty?

      lines = [ content.rstrip, "", "---", "👤 主催者プロフィール" ]
      lines << text if text.present?
      lines << "▶ 紹介動画: #{youtube_url}" if youtube_url.present?
      lines.join("\n")
    end

    def format_date(event_date, event_time, event_end_time)
      d   = Date.parse(event_date)
      dow = %w[日 月 火 水 木 金 土][d.wday]
      "#{d.year}年#{d.month}月#{d.day}日（#{dow}） #{event_time}〜#{event_end_time}"
    end

    LINE_RULES = <<~RULES.freeze
      【LINE向け文章ルール】
      - スマホのLINEで読まれる文章です。1行は短く端的に（目安：全角20〜25文字以内）
      - 長い一文は途中で改行せず、最初から短い文に分けて書く
      - リスト項目（・✅📌）は1行で収まる長さにする。収まらない場合は内容を絞って短くする
      - 読者がスクロールせず一目で把握できる密度を意識する
      - 各セクションの間は必ず1行の空行を入れること（空行とは空の1行のこと。「（空行）」という文字を出力しないこと）
    RULES

    # YouTube動画の文字起こしから、LINE配信向けの動画告知文を生成する
    def generate_youtube_announcement(api_key, video, extra_instruction = nil)
      transcript = video[:transcript].to_s[0, 9000]
      video_url  = "https://youtu.be/#{video[:video_id]}"

      system_prompt = <<~PROMPT
        あなたはLINE公式アカウント配信用の告知文を書くプロのコピーライターです。
        YouTube動画の文字起こしを読み、リスト読者が「今すぐ見たい」と思う動画告知文を生成してください。
        告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

        #{LINE_RULES}
        【告知文の作り方】
        - 冒頭2行は読者のベネフィットが伝わるフック（数字・実話・ビフォーアフターが有効）
        - 動画の内容は要約ではなく「見どころの予告」として書く（結論のネタバレはしない）
        - 文字起こしにある具体的な数字・エピソードを1つ以上フックに使う
        - 会話調で温度感を出す。絵文字は2〜3個まで
        - 動画URLは指定されたものをそのまま使う

        【出力フォーマット（この通りの改行・空行で出力すること）】
        {フック1行目}
        {フック2行目}

        {動画の紹介 1〜2文}

        この動画でわかること
        📌 {見どころ1}
        📌 {見どころ2}
        📌 {見どころ3}

        ▶ 動画はこちら
        {動画URL}

        {クロージングCTA 1〜2文}
      PROMPT

      user_prompt = <<~USER
        【動画タイトル】#{video[:title]}
        【動画URL】#{video_url}
        #{extra_instruction ? "【追加指示】#{extra_instruction}\n" : ''}
        【文字起こし】
        #{transcript}
      USER

      call_openai(api_key, system: system_prompt, user: user_prompt, temperature: 0.7)
    end

    def build_generate_prompts(title, is_event, sub_type, date_str, zoom_url = nil, meeting_id = nil, passcode = nil)
      if !is_event
        system = "あなたは受講生サポートのメッセージ作成プロです。タイトルに沿って、受講生に寄り添う温かみのあるサポートメッセージを生成してください。押し付けがましくなく、励ましや次のステップを示す内容にしてください。"
        user   = "以下のタイトルに沿った文章を生成してください：\n\n#{title}"
      elsif sub_type.blank?
        # LME未チェック：汎用イベント告知プロンプト（スマホ向けフォーマット）
        system = <<~PROMPT
          あなたはイベント告知文の作成プロです。タイトルに沿って、スマホで読みやすい告知文を生成してください。告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

          #{LINE_RULES}
          【出力フォーマット（この通りの改行・空行で出力すること）】
          {キャッチコピー1行目}
          {キャッチコピー2行目（任意）}

          こんな悩みはありませんか？

          ・{悩み1}
          ・{悩み2}
          ・{悩み3}
          ・{悩み4}
          ・{悩み5}

          放置するとこんなリスクが…
          ✅ {リスク1}
          ✅ {リスク2}
          ✅ {リスク3}
          ✅ {リスク4}

          今回のセミナーで得られること
          📌 {得られること1}
          📌 {得られること2}
          📌 {得られること3}

          {クロージング1〜2文}

          開催概要
          日時：#{date_str}
          対象：プログラミングに興味がある方・初学者の方

          👉 {CTA}
        PROMPT
        user = "タイトル：#{title}\n\n開催日時は必ず「#{date_str}」をそのまま使用してください。"
      elsif sub_type == "taiken"
        system = <<~PROMPT
          あなたはLINE配信用のイベント告知文の作成プロです。「体験会（セミナー）」の告知文を以下の構成・形式で生成してください。告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

          #{LINE_RULES}
          【出力フォーマット（この通りの改行・空行で出力すること）】
          {タイトル}

          こんな悩みはありませんか？

          ・{悩み1}
          ・{悩み2}
          ・{悩み3}
          ・{悩み4}
          ・{悩み5}

          放置するとこんなリスクが…
          ✅ {リスク1}
          ✅ {リスク2}
          ✅ {リスク3}
          ✅ {リスク4}

          今回のセミナーで得られること
          📌 {得られること1}
          📌 {得られること2}
          📌 {得られること3}

          {クロージング1〜2文}

          開催概要
          日時：#{date_str}
          対象：プログラミングに興味がある方・初学者の方

          👉 {CTA}
        PROMPT
        user = "タイトル：#{title}\n\n開催日時は必ず「#{date_str}」をそのまま使用してください。"
      else
        # 受講生勉強会
        system = <<~PROMPT
          あなたはLINE配信用のイベント告知文の作成プロです。「受講生勉強会」の告知文を以下の構成・形式で生成してください。告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

          #{LINE_RULES}
          【出力フォーマット（この通りの改行・空行で出力すること）】
          {タイトル}

          こんな悩みはありませんか？

          ・{悩み1}
          ・{悩み2}
          ・{悩み3}
          ・{悩み4}
          ・{悩み5}

          放置するとこんなリスクが…
          ✅ {リスク1}
          ✅ {リスク2}
          ✅ {リスク3}
          ✅ {リスク4}

          今回の勉強会で得られること
          📌 {得られること1}
          📌 {得られること2}
          📌 {得られること3}

          {クロージング1〜2文}

          開催概要
          日時：#{date_str}
          対象：プロアカ受講生

          👉 {CTA}
        PROMPT
        user = "タイトル：#{title}\n\n開催日時は必ず「#{date_str}」をそのまま使用してください。"
      end
      [ system, user ]
    end
  end
end
