require 'net/http'
require 'json'

module Api
  class AiController < ApplicationController
    OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze

    def correct
      key  = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      text = params[:text]
      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { error: 'テキストを入力してください' }, status: :bad_request unless text&.strip&.present?

      result = call_openai(key,
        system: 'あなたは文章添削のプロです。入力されたテキストを、誤字脱字の修正・表現の改善・読みやすさの向上を行い、改善版を返してください。元の意図やトーンは保ちつつ、より伝わりやすい文章にしてください。改善版のみを返し、説明は不要です。',
        user: text,
        temperature: 0.3
      )
      render json: { corrected: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def generate
      key           = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      title         = params[:title]
      type          = params[:type]
      event_date    = params[:eventDate]
      event_time    = params[:eventTime]    || '10:00'
      event_end_time = params[:eventEndTime] || '12:00'
      event_sub_type = params[:eventSubType] || 'benkyokai'

      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { error: '名前（タイトル）を入力してください' }, status: :bad_request unless title&.strip&.present?
      return render json: { error: '開催日時の日付を入力してください' }, status: :bad_request unless event_date&.strip&.present?

      date_str = format_date(event_date, event_time, event_end_time)
      is_event = type != 'student'

      system_prompt, user_prompt = build_generate_prompts(title, is_event, event_sub_type, date_str)

      result = call_openai(key, system: system_prompt, user: user_prompt, temperature: 0.7)
      render json: { content: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def align_datetime
      key           = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      text          = params[:text]
      event_date    = params[:eventDate]
      event_time    = params[:eventTime]    || '10:00'
      event_end_time = params[:eventEndTime] || '12:00'

      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { content: text } unless text&.strip&.present? && event_date

      date_str = format_date(event_date, event_time, event_end_time)
      result = call_openai(key,
        system: 'あなたはテキスト編集のアシスタントです。文章中に記載されている開催日時・日付・時刻の部分のみを、指定された日時に差し替えてください。文章の他の部分は一切変更しないでください。修正後のテキスト全体のみを返してください。',
        user: "開催日時を「#{date_str}」に合わせてください。\n\n#{text}",
        temperature: 0.1
      )
      render json: { content: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def agent
      key    = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      text   = params[:text]
      prompt = params[:prompt]

      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { error: '指示を入力してください' }, status: :bad_request unless prompt&.strip&.present?

      result = call_openai(key,
        system: 'あなたは文章作成のアシスタントです。ユーザーの現在のテキストに対して、ユーザーの指示に従って修正・改善した結果を返してください。結果のテキストのみを返し、余分な説明は不要です。',
        user: "【現在のテキスト】\n#{text.presence || '(空)'}\n\n【指示】\n#{prompt}",
        temperature: 0.5
      )
      render json: { result: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    private

    def call_openai(api_key, system:, user:, temperature: 0.5)
      uri  = URI(OPENAI_API_URL)
      req  = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{api_key}"
      req['Content-Type']  = 'application/json'
      req.body = {
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: system },
          { role: 'user',   content: user },
        ],
        temperature: temperature,
      }.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      res  = http.request(req)
      data = JSON.parse(res.body)
      raise data.dig('error', 'message') || 'OpenAI APIエラー' unless res.is_a?(Net::HTTPSuccess)

      data.dig('choices', 0, 'message', 'content')&.strip || ''
    end

    def format_date(event_date, event_time, event_end_time)
      d   = Date.parse(event_date)
      dow = %w[日 月 火 水 木 金 土][d.wday]
      "#{d.year}年#{d.month}月#{d.day}日（#{dow}） #{event_time}〜#{event_end_time}"
    end

    def build_generate_prompts(title, is_event, sub_type, date_str)
      if !is_event
        system = 'あなたは受講生サポートのメッセージ作成プロです。タイトルに沿って、受講生に寄り添う温かみのあるサポートメッセージを生成してください。押し付けがましくなく、励ましや次のステップを示す内容にしてください。'
        user   = "以下のタイトルに沿った文章を生成してください：\n\n#{title}"
      elsif sub_type == 'taiken'
        system = <<~PROMPT
          あなたはイベント告知文の作成プロです。「体験会（セミナー）」の告知文を以下の構成・形式で生成してください。告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

          【構成】
          1行目：タイトルをそのまま記載
          （空行）
          こんな悩みはありませんか？
          （空行）
          ・悩み（5項目、各1行）
          （空行）
          放置するとこんなリスクが…
          ✅ リスク（4項目、各1行）
          （空行）
          今回のセミナーで得られること
          📌 得られること（3項目、各1行）
          （空行）
          タイトルの内容に合った感情を動かすクロージング1〜2文
          （空行）
          開催概要
          日時：#{date_str}
          対象：プログラミングに興味がある方・初学者の方
          参加URL： （後ほど共有）
          （空行）
          ミーティング ID: （後ほど共有）
          パスコード: （後ほど共有）
          （空行）
          👉 参加を促すCTA（1行）
        PROMPT
        user = "タイトル：#{title}\n\n開催日時は必ず「#{date_str}」をそのまま使用してください。"
      else
        system = <<~PROMPT
          あなたはイベント告知文の作成プロです。「受講生勉強会」の告知文を以下の構成・形式で生成してください。告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

          【構成】
          1行目：タイトルをそのまま記載
          （空行）
          こんな悩みはありませんか？
          （空行）
          ・悩み（5項目、各1行）
          （空行）
          放置するとこんなリスクが…
          ✅ リスク（4項目、各1行）
          （空行）
          今回の勉強会で得られること
          📌 得られること（3項目、各1行）
          （空行）
          タイトルの内容に合った感情を動かすクロージング1〜2文
          （空行）
          開催概要
          日時：#{date_str}
          対象：プロアカ受講生
          参加URL： （後ほど共有）
          （空行）
          ミーティング ID: （後ほど共有）
          パスコード: （後ほど共有）
          （空行）
          👉 参加を促すCTA（1行）
        PROMPT
        user = "タイトル：#{title}\n\n開催日時は必ず「#{date_str}」をそのまま使用してください。"
      end
      [system, user]
    end
  end
end
