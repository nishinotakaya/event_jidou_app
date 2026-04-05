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
    generate_image = payload['generateImage']
    image_style    = payload['imageStyle'] || 'cute'
    openai_key     = payload['openaiApiKey'].presence || ENV['OPENAI_API_KEY']
    dalle_key      = payload['dalleApiKey'].presence || AppSetting.get('dalle_api_key') || openai_key

    broadcast(job_id, type: 'log', message: '投稿処理を開始します...')

    # ===== 画像生成（DALL-E 3） =====
    image_path = nil
    if generate_image
      if dalle_key.blank?
        broadcast(job_id, type: 'log', message: '⚠️ 画像生成: DALL-E APIキーが未設定のためスキップします')
      else
        begin
          broadcast(job_id, type: 'log', message: '🖼️ DALL-E 3で画像生成中...')
          image_title = event_fields['title'].presence || content.split("\n").first.to_s[0, 80]
          image_path  = generate_dalle_image(dalle_key, image_title, image_style, job_id)
          broadcast(job_id, type: 'log', message: '🖼️ 画像生成・保存完了')
        rescue => e
          broadcast(job_id, type: 'log', message: "⚠️ 画像生成失敗: #{e.message}")
        end
      end
    end

    playwright_path = find_playwright_path

    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      # headless: false — PeatixのFormKit等、headlessでは座標クリックが効かないUIがあるため
      browser = playwright.chromium.launch(
        headless: false,
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

      # SNS（X/Instagram）はポータルサイト投稿後に実行（申し込みURLを取得するため）
      sns_sites = %w[X Instagram]
      portal_sites = sites.reject { |s| sns_sites.include?(s.split(':').first) }
      deferred_sites = sites.select { |s| sns_sites.include?(s.split(':').first) }

      broadcast(job_id, type: 'log', message: "🚀 #{portal_sites.length}サイトを並列投稿開始...#{deferred_sites.any? ? "（SNS #{deferred_sites.length}件は後から投稿）" : ''}")

      # ===== ポータルサイト: 並列実行 =====
      threads = portal_sites.map do |site_key|
        Thread.new do
          site_name, sub_type = site_key.split(':', 2)
          ef = event_fields.merge(
            'lmeAccount' => (sub_type || event_fields['lmeAccount'] || 'taiken'),
            'imagePath'  => image_path,
          )

          context_opts = {
            userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
            locale: 'ja-JP',
            viewport: { width: 1280, height: 800 },
          }
          # セッションファイルがあれば復元（つなゲート等）
          session_file = Rails.root.join('tmp', "#{SITE_TO_SERVICE[site_name]}_session.json").to_s
          if File.exist?(session_file)
            context_opts[:storageState] = session_file
            broadcast(job_id, type: 'log', message: "[#{site_name}] セッション復元")
          end
          context = browser.new_context(**context_opts)
          page = context.new_page

          broadcast(job_id, type: 'status', site: site_name, status: 'running')
          broadcast(job_id, type: 'log',    message: "[#{site_name}] 開始...")

          begin
            # ログからイベントURLを抽出するためのキャプチャ
            captured_urls = []
            log_fn = ->(msg) {
              broadcast(job_id, type: 'log', message: msg)
              # ログ内のURLをキャプチャ
              msg.to_s.scan(%r{https?://[^\s））」]+}).each { |url| captured_urls << url }
            }

            case site_name
            when 'こくチーズ' then Posting::KokuchproService.new.call(page, content, ef, &log_fn)
            when 'Peatix'     then Posting::PeatixService.new.call(page, content, ef, &log_fn)
            when 'connpass'   then Posting::ConnpassService.new.call(page, content, ef, &log_fn)
            when 'TechPlay'    then Posting::TechplayService.new.call(page, content, ef, &log_fn)
            when 'つなゲート'   then Posting::TunagateService.new.call(page, content, ef, &log_fn)
            when 'Doorkeeper' then Posting::DoorkeeperService.new.call(page, content, ef, &log_fn)
            when 'セミナーズ'   then Posting::SeminarsService.new.call(page, content, ef, &log_fn)
            when 'ストアカ'    then Posting::StreetAcademyService.new.call(page, content, ef, &log_fn)
            when 'EventRegist' then Posting::EventregistService.new.call(page, content, ef, &log_fn)
            when 'PassMarket'  then Posting::PassmarketService.new.call(page, content, ef, &log_fn)
            when 'Luma'        then Posting::LumaService.new.call(page, content, ef, &log_fn)
            when 'セミナーBiZ' then Posting::SeminarBizService.new.call(page, content, ef, &log_fn)
            when 'ジモティー'   then Posting::JimotyService.new.call(page, content, ef, &log_fn)
            when 'LME'         then Posting::LmeService.new.call(page, content, ef, &log_fn)
            when 'Gmail'        then Posting::GmailService.new.call(page, content, ef, &log_fn)
            when 'X'            then Posting::TwitterService.new.call(page, content, ef, &log_fn)
            when 'Instagram'    then Posting::InstagramService.new.call(page, content, ef, &log_fn)
            when 'オンクラス'   then Posting::OnclassService.new.call(page, content, ef, &log_fn)
            else broadcast(job_id, type: 'log', message: "[#{site_name}] 未対応サイトです")
            end

            # イベント詳細URLを特定（ログ内のURL or page.url からイベントIDを含むものを優先）
            event_url = pick_event_url(site_name, page.url, captured_urls)

            broadcast(job_id, type: 'status', site: site_name, status: 'success')
            broadcast(job_id, type: 'log', message: "[#{site_name}] 📌 イベントURL: #{event_url}") if event_url.present?
            update_connection_status(site_name, 'connected')
            save_posting_history(item_id, site_name, 'success', event_url, ef.dig('publishSites', site_name))
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

      threads.each(&:join)

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
    'オンクラス'   => 'onclass',
  }.freeze

  # 各サイトのイベント詳細URLパターンに基づいて最適なURLを選択
  EVENT_URL_PATTERNS = {
    'こくチーズ'   => %r{kokuchpro\.com/(?:admin|event)/e-[\w]+/d-\d+},
    'connpass'     => %r{connpass\.com/event/\d+(?:/edit)?/?},
    'Peatix'       => %r{peatix\.com/event/\d+(?!.*edit)},
    'TechPlay'     => %r{techplay\.jp/event/\d+(?!.*edit)},
    'つなゲート'   => %r{tunagate\.com/circle/\d+/events/\d+},
    'Doorkeeper'   => %r{doorkeeper\.jp/.+/events/\d+(?!.*edit)},
    'セミナーズ'   => %r{seminars\.jp/s/\d+},
    'ストアカ'     => %r{street-academy\.com/myclass/\d+},
    'EventRegist'  => %r{eventregist\.com/e/\w+},
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
      unless File.exist?(wrapper)
        File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
        File.chmod(0o755, wrapper)
      end
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
