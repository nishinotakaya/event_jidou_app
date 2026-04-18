require 'playwright'
require 'net/http'
require 'open-uri'
require 'json'
require 'shellwords'

class PostJob < ApplicationJob
  queue_as :default

  def perform(job_id, payload)
    content        = payload['content'].to_s
    sites          = Array(payload['sites'])
    event_fields   = payload['eventFields'] || {}
    item_id        = payload['itemId'].presence
    posting_user_id = payload['userId']
    posting_user    = User.find_by(id: posting_user_id)
    generate_image = payload['generateImage']
    image_style    = payload['imageStyle'] || 'cute'
    openai_key     = payload['openaiApiKey'].presence || ENV['OPENAI_API_KEY']
    dalle_key      = payload['dalleApiKey'].presence || AppSetting.get('dalle_api_key') || openai_key

    broadcast(job_id, type: 'log', message: '投稿処理を開始します...')

    # ===== 画像準備 =====
    # 優先順位: (1) 既存画像ID指定 → DBから復元、(2) DALL-E 自動生成
    image_path = nil
    generated_image_id = payload['generatedImageId'].presence

    if generated_image_id
      begin
        img = GeneratedImage.find(generated_image_id)
        ext = img.content_type.to_s.include?('jpeg') ? '.jpg' : '.png'
        image_path = Rails.root.join('tmp', "picked_image_#{Time.now.to_i}_#{job_id}#{ext}").to_s
        File.write(image_path, img.data, mode: 'wb')
        broadcast(job_id, type: 'log', message: "🖼️ 既存画像を使用（id=#{img.id}, #{img.byte_size}B）")
      rescue ActiveRecord::RecordNotFound
        broadcast(job_id, type: 'log', message: "⚠️ 指定された画像(id=#{generated_image_id})が見つかりません")
      end
    end

    # 画像が未指定の場合は常にAI生成（ストアカ等で必須）
    generate_image = true if image_path.nil?
    if image_path.nil? && generate_image
      if dalle_key.blank?
        broadcast(job_id, type: 'log', message: '⚠️ 画像生成: DALL-E APIキーが未設定のためスキップします')
      else
        begin
          broadcast(job_id, type: 'log', message: '🖼️ DALL-E 3で画像生成中...')
          image_title = event_fields['title'].presence || content.split("\n").first.to_s[0, 80]
          image_path  = generate_dalle_image(dalle_key, image_title, image_style, job_id)
          # DB保存（再利用可能にする）
          begin
            bytes = File.binread(image_path)
            GeneratedImage.create!(
              user_id: posting_user_id,
              source: 'dalle',
              filename: File.basename(image_path),
              content_type: 'image/png',
              byte_size: bytes.bytesize,
              prompt: image_title,
              style: image_style,
              item_id: item_id,
              data: bytes,
            )
            # JawsDB 5MB上限対策: 古い画像を削除して最新3枚のみ保持
            excess = GeneratedImage.order(created_at: :desc).offset(3).pluck(:id)
            GeneratedImage.where(id: excess).delete_all if excess.any?
            broadcast(job_id, type: 'log', message: '🖼️ 画像生成・DB保存完了')
          rescue => e
            broadcast(job_id, type: 'log', message: "⚠️ 画像DB保存失敗: #{e.message}（ファイルは保持）")
          end
        rescue => e
          broadcast(job_id, type: 'log', message: "⚠️ 画像生成失敗: #{e.message}")
        end
      end
    end

    playwright_path = find_playwright_path

    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      # 本番（Heroku）はheadless必須、ローカルはheadless: falseも可
      browser = playwright.chromium.launch(
        headless: ENV['RAILS_ENV'] == 'production',
        args: [
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-blink-features=AutomationControlled',
          '--disable-dev-shm-usage',      # コンテナ内 /dev/shm(64MB) 枯渇クラッシュを防ぐ（最重要）
          '--disable-gpu',                # GPUなし環境でのクラッシュ防止
          '--disable-extensions',
          '--disable-default-apps',
          '--no-first-run',
          '--disable-background-networking',
          '--disable-sync',
        ],
      )

      # オンクラスは「受講生サポート」タブからの投稿のみ許可
      post_type = payload['postType'].to_s
      unless post_type == 'student'
        skipped = sites.select { |s| s.split(':').first == 'オンクラス' }
        sites = sites.reject { |s| s.split(':').first == 'オンクラス' }
        skipped.each do |s|
          broadcast(job_id, type: 'log', message: "[オンクラス] ⏭️ 受講生サポート以外ではスキップ")
          broadcast(job_id, type: 'status', site: s.split(':').first, status: 'skipped')
        end
      end

      # ストアカ公開時は画像必須（サイト側の必須項目 / 2,000円 上限）
      publishing_street = sites.any? { |s| s.split(':').first == 'ストアカ' } && event_fields.dig('publishSites', 'ストアカ')
      ef_image = event_fields['imagePath'].to_s.presence
      if publishing_street && image_path.blank? && ef_image.blank?
        sites = sites.reject { |s| s.split(':').first == 'ストアカ' }
        broadcast(job_id, type: 'log', message: "[ストアカ] ❌ 公開するには画像が必須です。DALL-E自動生成をONにするか、過去画像を選択してから再実行してください。")
        broadcast(job_id, type: 'status', site: 'ストアカ', status: 'error')
        save_posting_history(item_id, 'ストアカ', 'error', nil, false, '画像未指定（ストアカ公開には画像必須）')
      end

      # SNS（X/Instagram）はポータルサイト投稿後に実行（申し込みURLを取得するため）
      sns_sites = %w[X Instagram]
      portal_sites = sites.reject { |s| sns_sites.include?(s.split(':').first) }
      deferred_sites = sites.select { |s| sns_sites.include?(s.split(':').first) }

      # 本番はメモリ節約のためサイトごとにブラウザ再起動、ローカルは並列
      sequential = ENV['RAILS_ENV'] == 'production'
      broadcast(job_id, type: 'log', message: "🚀 #{portal_sites.length}サイトを#{sequential ? '順次' : '並列'}投稿開始...#{deferred_sites.any? ? "（SNS #{deferred_sites.length}件は後から投稿）" : ''}")

      # ===== 1サイト投稿処理 =====
      post_one_site = ->(site_key, shared_browser) do
        site_name, sub_type = site_key.split(':', 2)
        ef = event_fields.merge(
          'lmeAccount' => (sub_type || event_fields['lmeAccount'] || 'taiken'),
          'imagePath'  => image_path,
        )

        # 本番: サイトごとにブラウザ起動→終了（メモリ解放）
        # ローカル: 共有ブラウザを使用
        site_browser = shared_browser
        pw_instance = nil
        if sequential
          pw_instance = Playwright.create(playwright_cli_executable_path: playwright_path)
          site_browser = pw_instance.playwright.chromium.launch(
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled',
                   '--disable-dev-shm-usage', '--disable-gpu', '--disable-extensions', '--no-first-run'],
          )
        end

        context_opts = {
          userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
          locale: 'ja-JP',
          viewport: { width: 1280, height: 800 },
        }
        service_key = SITE_TO_SERVICE[site_name]
        svc_conn = posting_user ? posting_user.service_connections.find_by(service_name: service_key) : ServiceConnection.find_by(service_name: service_key)
        if svc_conn&.session_data.present?
          begin
            context_opts[:storageState] = JSON.parse(svc_conn.session_data)
            broadcast(job_id, type: 'log', message: "[#{site_name}] DBセッション復元")
          rescue JSON::ParserError
            broadcast(job_id, type: 'log', message: "[#{site_name}] セッション破損 - 新規ログイン")
          end
        end

        context = site_browser.new_context(**context_opts)
        page = context.new_page

        broadcast(job_id, type: 'status', site: site_name, status: 'running')
        broadcast(job_id, type: 'log',    message: "[#{site_name}] 開始...")

        begin
          captured_urls = []
          log_fn = ->(msg) {
            broadcast(job_id, type: 'log', message: msg)
            msg.to_s.scan(%r{https?://[^\s））」]+}).each { |url| captured_urls << url }
          }

          # 既存投稿があれば更新（編集）、なければ新規作成
          existing = item_id.present? ? PostingHistory.find_by(item_id: item_id, site_name: service_key, status: 'success') : nil
          svc_class = {
            'こくチーズ' => Posting::KokuchproService, 'Peatix' => Posting::PeatixService,
            'connpass' => Posting::ConnpassService, 'TechPlay' => Posting::TechplayService,
            'つなゲート' => Posting::TunagateService, 'Doorkeeper' => Posting::DoorkeeperService,
            'セミナーズ' => Posting::SeminarsService, 'ストアカ' => Posting::StreetAcademyService,
            'EventRegist' => Posting::EventregistService, 'PassMarket' => Posting::PassmarketService,
            'Luma' => Posting::LumaService, 'セミナーBiZ' => Posting::SeminarBizService,
            'ジモティー' => Posting::JimotyService, 'LME' => Posting::LmeService,
            'Gmail' => Posting::GmailService, 'X' => Posting::TwitterService,
            'Instagram' => Posting::InstagramService, 'オンクラス' => Posting::OnclassService,
            'Facebook' => Posting::FacebookService,
          }[site_name]

          if svc_class.nil?
            broadcast(job_id, type: 'log', message: "[#{site_name}] 未対応サイトです")
          elsif existing&.event_url.present?
            # 既存投稿あり → 更新
            broadcast(job_id, type: 'log', message: "[#{site_name}] 📝 既存投稿を更新中... (#{existing.event_url})")
            begin
              svc_class.new.update_remote(page, existing.event_url, content, ef, &log_fn)
            rescue NotImplementedError
              broadcast(job_id, type: 'log', message: "[#{site_name}] ⚠️ 更新未対応 → 新規作成にフォールバック")
              svc_class.new.call(page, content, ef, &log_fn)
            end
          else
            # 新規作成
            svc_class.new.call(page, content, ef, &log_fn)
          end

          event_url = pick_event_url(site_name, page.url, captured_urls)
          if EVENT_URL_PATTERNS.key?(site_name) && event_url.blank?
            raise "イベントURLを検出できませんでした。公開処理が完了していない可能性があります（最終URL: #{page.url}）"
          end
          broadcast(job_id, type: 'status', site: site_name, status: 'success')
          broadcast(job_id, type: 'log', message: "[#{site_name}] 📌 イベントURL: #{event_url}") if event_url.present?
          update_connection_status(site_name, 'connected')
          save_posting_history(item_id, site_name, 'success', event_url, ef.dig('publishSites', site_name))
          save_session_to_db(context, service_key)
        rescue => e
          broadcast(job_id, type: 'log',    message: "[#{site_name}] ❌ エラー: #{e.message}")
          broadcast(job_id, type: 'status', site: site_name, status: 'error')
          update_connection_status(site_name, 'error', e.message)
          save_posting_history(item_id, site_name, 'error', nil, false, e.message)
        ensure
          context.close rescue nil
          if sequential
            site_browser.close rescue nil
            pw_instance.close rescue nil
          end
        end
      end

      # ===== 実行 =====
      if sequential
        # 本番: サイトごとにブラウザ起動→投稿→終了（メモリ完全解放）
        portal_sites.each { |site_key| post_one_site.call(site_key, nil) }
      else
        # ローカル: 共有ブラウザで並列
        threads = portal_sites.map { |site_key| Thread.new { post_one_site.call(site_key, browser) } }
        threads.each(&:join)
      end

      # ===== SNS: ポータルサイト投稿後に実行（申し込みURLを含めるため） =====
      if deferred_sites.any?
        broadcast(job_id, type: 'log', message: "📱 SNS投稿開始 (#{deferred_sites.length}件)...")

        deferred_sites.each do |site_key|
          site_name, sub_type = site_key.split(':', 2)
          ef = event_fields.merge(
            'lmeAccount' => (sub_type || event_fields['lmeAccount'] || 'taiken'),
            'imagePath'  => image_path,
            'itemId'     => item_id,
          )

          context_opts = {
            userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
            locale: 'ja-JP',
            viewport: { width: 1280, height: 800 },
          }
          session_file = Rails.root.join('tmp', "#{SITE_TO_SERVICE[site_name]}_session.json").to_s
          context_opts[:storageState] = session_file if File.exist?(session_file)
          context = browser.new_context(**context_opts)
          page = context.new_page

          broadcast(job_id, type: 'status', site: site_name, status: 'running')

          begin
            captured_urls = []
            log_fn = ->(msg) {
              broadcast(job_id, type: 'log', message: msg)
              msg.to_s.scan(%r{https?://[^\s））」]+}).each { |url| captured_urls << url }
            }

            case site_name
            when 'X'         then Posting::TwitterService.new.call(page, content, ef, &log_fn)
            when 'Instagram' then Posting::InstagramService.new.call(page, content, ef, &log_fn)
            end

            event_url = pick_event_url(site_name, page.url, captured_urls)
            broadcast(job_id, type: 'status', site: site_name, status: 'success')
            update_connection_status(site_name, 'connected')
            save_posting_history(item_id, site_name, 'success', event_url, true)
          rescue => e
            broadcast(job_id, type: 'log',    message: "[#{site_name}] ❌ エラー: #{e.message}")
            broadcast(job_id, type: 'status', site: site_name, status: 'error')
            update_connection_status(site_name, 'error', e.message)
            save_posting_history(item_id, site_name, 'error', nil, false, e.message)
          ensure
            context.close rescue nil
          end
        end
      end

      browser.close rescue nil
    end

    broadcast(job_id, type: 'log', message: '✅ 全サイト処理完了')
    broadcast(job_id, type: 'done')
  rescue => e
    broadcast(job_id, type: 'error', message: e.message)
    broadcast(job_id, type: 'done')
  ensure
    File.delete(image_path) if image_path && File.exist?(image_path) rescue nil
  end

  private

  def broadcast(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end

  SITE_TO_SERVICE = {
    'こくチーズ'   => 'kokuchpro',
    'Peatix'       => 'peatix',
    'connpass'     => 'connpass',
    'TechPlay'     => 'techplay',
    'つなゲート'   => 'tunagate',
    'Doorkeeper'   => 'doorkeeper',
    'セミナーズ'   => 'seminars',
    'ストアカ'     => 'street_academy',
    'EventRegist'  => 'eventregist',
    'PassMarket'   => 'passmarket',
    'everevo'      => 'everevo',
    'Luma'         => 'luma',
    'セミナーBiZ'  => 'seminar_biz',
    'ジモティー'   => 'jimoty',
    'LME'         => 'lme',
    'Gmail'        => 'gmail',
    'X'            => 'twitter',
    'Instagram'    => 'instagram',
    'Facebook'     => 'facebook',
    'Threads'      => 'threads',
    'オンクラス'   => 'onclass',
  }.freeze

  # 各サイトのイベント詳細URLパターンに基づいて最適なURLを選択
  EVENT_URL_PATTERNS = {
    'こくチーズ'   => %r{kokuchpro\.com/(?:admin|event)/e-[\w]+/d-\d+},
    'connpass'     => %r{connpass\.com/event/\d+(?:/edit)?/?},
    'Peatix'       => %r{peatix\.com/event/\d+(?!.*edit)},
    'TechPlay'     => %r{techplay\.jp/event/\d+(?!.*edit)},
    'つなゲート'   => %r{tunagate\.com/(?:circle/\d+/events/\d+|events?/(?:edit/)?\d+)},
    'Doorkeeper'   => %r{doorkeeper\.jp/.+/events/\d+(?!.*edit)},
    'セミナーズ'   => %r{seminars\.jp/s/\d+},
    'ストアカ'     => %r{street-academy\.com/myclass/\d+},
    'EventRegist'  => %r{eventregist\.com/(?:e/\w+|event/\w+|dashboard)},
    'PassMarket'   => %r{passmarket\.yahoo\.co\.jp/event/\w+},
    'Luma'         => %r{luma\.com/event/manage/evt-\w+|lu\.ma/event/manage/evt-\w+},
    'セミナーBiZ'  => %r{seminar-biz\.com/seminar/\d+/events/\d+},
    'ジモティー'   => %r{jmty\.jp/\w+/\w+-\w+/article-\w+},
  }.freeze

  def pick_event_url(site_name, page_url, captured_urls)
    pattern = EVENT_URL_PATTERNS[site_name]
    return page_url unless pattern

    # 1. ログ内のURLからパターンマッチするものを優先（最後にマッチしたものが最も正確）
    all_urls = captured_urls + [page_url]
    matched = all_urls.select { |url| url.match?(pattern) }.last
    return matched if matched

    # 2. page.urlがedit/create等を含まなければ使用
    return page_url unless page_url.match?(/create|new|sign_in|login|dashboard|manage|editmanage/)

    # 3. マッチしない場合はnilを返す（不正なURLを保存しない）
    nil
  end

  def save_posting_history(item_id, site_name, status, event_url = nil, published = false, error_msg = nil)
    return if item_id.blank?
    service = SITE_TO_SERVICE[site_name]
    svc_name = service || site_name

    # 既存の履歴があれば上書き（同じitem+siteの最新を更新）
    existing = PostingHistory.where(item_id: item_id, site_name: svc_name).order(posted_at: :desc).first
    if existing
      existing.update!(
        status: status,
        event_url: event_url.presence || existing.event_url,
        published: published || false,
        error_message: error_msg,
        posted_at: Time.current,
      )
    else
      PostingHistory.create!(
        item_id: item_id,
        site_name: svc_name,
        status: status,
        event_url: event_url,
        published: published || false,
        error_message: error_msg,
        posted_at: Time.current,
      )
    end
  rescue => e
    Rails.logger.warn("[PostJob] posting history save failed: #{e.message}")
  end

  def save_session_to_db(context, service_key)
    return unless service_key
    conn = ServiceConnection.find_by(service_name: service_key)
    return unless conn
    state = context.storage_state
    conn.update!(session_data: state.to_json)
  rescue => e
    Rails.logger.warn("[PostJob] セッションDB保存失敗: #{e.message}")
  end

  def update_connection_status(site_name, status, error_msg = nil)
    service = SITE_TO_SERVICE[site_name]
    return unless service
    conn = ServiceConnection.find_by(service_name: service)
    return unless conn
    attrs = { status: status, error_message: error_msg }
    attrs[:last_connected_at] = Time.current if status == 'connected'
    conn.update!(attrs)
  rescue => e
    Rails.logger.warn("[PostJob] connection status update failed: #{e.message}")
  end

  def find_playwright_path
    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    if File.exist?(local)
      # パスにスペースや日本語が含まれる場合、ラッパースクリプト経由で実行
      wrapper = '/tmp/playwright-runner.sh'
      File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"\$@\"\n")
      File.chmod(0o755, wrapper)
      return wrapper
    end
    # グローバルの npx を使用
    npx = `which npx`.strip
    npx.present? ? "#{npx} playwright" : 'npx playwright'
  end

  def generate_dalle_image(api_key, title, image_style, job_id)
    is_cute = image_style != 'cool'
    style_prompt = is_cute ?
      "Cute and kawaii style event banner for \"#{title}\". Pastel colors, soft watercolor illustration, adorable characters or flowers, warm and friendly atmosphere. No text. High quality." :
      "Cool and stylish event banner for \"#{title}\". Bold colors, modern geometric design, dynamic composition, sharp and professional look. No text. High quality."

    broadcast(job_id, type: 'log', message: "🖼️ スタイル: #{is_cute ? '🌸 可愛い系' : '⚡ かっこいい系'}")

    uri = URI('https://api.openai.com/v1/images/generations')
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type']  = 'application/json'
    req.body = { model: 'dall-e-3', prompt: style_prompt, n: 1, size: '1024x1024' }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120

    res  = http.request(req)
    data = JSON.parse(res.body)
    raise data.dig('error', 'message') || 'DALL-E APIエラー' unless res.is_a?(Net::HTTPSuccess)

    image_url = data.dig('data', 0, 'url')
    raise '画像URLが取得できませんでした' unless image_url

    broadcast(job_id, type: 'log', message: '🖼️ 画像URL取得完了。ダウンロード中...')
    image_data  = URI.open(image_url).read # rubocop:disable Security/Open
    image_path  = Rails.root.join('tmp', "event_image_#{Time.now.to_i}_#{job_id}.png").to_s
    File.write(image_path, image_data, mode: 'wb')
    image_path
  end
end
