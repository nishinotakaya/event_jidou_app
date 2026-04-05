require 'google/apis/gmail_v1'
require 'googleauth'

module Posting
  class GmailService < BaseService
    private

    def execute(_page, content, ef)
      user = User.first
      raise 'Googleアカウントが未連携です。ログインしてGmail権限を付与してください。' unless user&.google_access_token.present?

      title = extract_title(ef, content, 100)
      recipients = parse_recipients(ef)
      raise '送信先メールアドレスが指定されていません。eventFieldsのgmailTo/gmailRecipientsを設定してください。' if recipients.empty?

      # Zoom情報をメール本文に含める（告知文には入れないがメールには入れる）
      body = build_email_body(content, ef)

      gmail = Google::Apis::GmailV1::GmailService.new
      gmail.authorization = build_credentials(user)

      recipients.each do |to_addr|
        message = build_mime_message(
          from: user.email,
          to: to_addr,
          subject: title,
          body: body,
        )

        gmail_msg = Google::Apis::GmailV1::Message.new(raw: Base64.urlsafe_encode64(message))
        gmail.send_user_message('me', gmail_msg)
        log("[Gmail] 送信完了: #{to_addr}")
      end

      log("[Gmail] #{recipients.length}件のメール送信が完了しました")
    end

    def parse_recipients(ef)
      raw = ef['gmailTo'].presence || ef['gmailRecipients'].presence || ''
      raw.split(/[,;\s\n]+/).map(&:strip).select { |e| e.include?('@') }.uniq
    end

    def build_email_body(content, ef)
      body = content.dup

      zoom_url      = ef['zoomUrl'].to_s
      zoom_id       = ef['zoomId'].to_s
      zoom_passcode = ef['zoomPasscode'].to_s
      zoom_passcode = '' unless zoom_passcode.match?(/\A\d{4,10}\z/)

      if zoom_url.present?
        body += "\n\n━━━━━━━━━━━━━━━━"
        body += "\n■ Zoom参加情報"
        body += "\n━━━━━━━━━━━━━━━━"
        body += "\n参加URL: #{zoom_url}"
        body += "\nミーティングID: #{zoom_id}" if zoom_id.present?
        body += "\nパスコード: #{zoom_passcode}" if zoom_passcode.present?
        body += "\n\n※ 開始5分前になりましたらURLよりご入室ください。"
      end

      body
    end

    def build_credentials(user)
      creds = Google::Auth::UserRefreshCredentials.new(
        client_id: ENV['GOOGLE_CLIENT_ID'],
        client_secret: ENV['GOOGLE_CLIENT_SECRET'],
        scope: ['https://www.googleapis.com/auth/gmail.send'],
        additional_parameters: { access_type: 'offline' },
      )
      creds.access_token = user.google_access_token
      creds.refresh_token = user.google_refresh_token
      creds.expires_at = user.google_token_expires_at

      # トークンが期限切れの場合はリフレッシュ
      if user.google_token_expires_at && Time.current > user.google_token_expires_at
        log('[Gmail] アクセストークンをリフレッシュ中...')
        creds.fetch_access_token!
        user.update!(
          google_access_token: creds.access_token,
          google_token_expires_at: Time.at(creds.issued_at.to_i + creds.expires_in.to_i),
        )
      end

      creds
    end

    def build_mime_message(from:, to:, subject:, body:)
      # RFC 2822 形式のメールメッセージを構築
      encoded_subject = "=?UTF-8?B?#{Base64.strict_encode64(subject)}?="

      <<~MIME
        From: #{from}
        To: #{to}
        Subject: #{encoded_subject}
        MIME-Version: 1.0
        Content-Type: text/plain; charset=UTF-8
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64(body)}
      MIME
    end
  end
end
