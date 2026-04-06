require 'playwright'
require 'shellwords'

# リモートイベントの削除・中止を並列実行するバックグラウンドジョブ
class RemoteActionJob < ApplicationJob
  queue_as :default

  # action: 'delete', 'cancel', or 'publish'
  def perform(job_id, item_id, action)
    target_statuses = action == 'publish' ? %w[success draft] : %w[success]
    histories = PostingHistory.where(item_id: item_id, status: target_statuses)
      .where.not(event_url: [nil, '', 'about:blank'])

    # publish時は未公開のみ対象
    histories = histories.where(published: false) if action == 'publish'

    if histories.empty?
      broadcast(job_id, type: 'log', message: action == 'publish' ? '公開対象のサイトがありません' : '投稿済みサイトがありません')
      broadcast(job_id, type: 'done')
      return
    end

    action_label = { 'delete' => '削除', 'cancel' => '中止', 'publish' => '公開' }[action] || action
    broadcast(job_id, type: 'log', message: "#{action_label}処理を開始します... (#{histories.count}サイト)")

    playwright_path = find_playwright_path

    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      browser = playwright.chromium.launch(
        headless: false,
        args: [
          '--no-sandbox', '--disable-setuid-sandbox',
          '--disable-blink-features=AutomationControlled',
          '--disable-dev-shm-usage', '--disable-gpu',
        ],
      )

      threads = histories.map do |history|
        Thread.new do
          site_name = history.site_name
          event_url = history.event_url
          service = service_for(site_name)

          unless service
            broadcast(job_id, type: 'log', message: "[#{site_name}] 未対応サービスです")
            next
          end

          context_opts = {
            userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
            locale: 'ja-JP',
            viewport: { width: 1280, height: 800 },
          }
          session_file = Rails.root.join('tmp', "#{site_name}_session.json").to_s
          context_opts[:storageState] = session_file if File.exist?(session_file)

          context = browser.new_context(**context_opts)
          page = context.new_page

          broadcast(job_id, type: 'status', site: display_name(site_name), status: 'running')
          broadcast(job_id, type: 'log', message: "[#{display_name(site_name)}] #{action_label}開始...")

          begin
            log_fn = ->(msg) { broadcast(job_id, type: 'log', message: msg) }

            case action
            when 'delete'
              service.delete_remote(page, event_url, &log_fn)
              history.update!(status: 'deleted', error_message: nil)
            when 'cancel'
              service.cancel_remote(page, event_url, &log_fn)
              history.update!(status: 'cancelled', error_message: nil)
            when 'publish'
              service.publish_remote(page, event_url, &log_fn)
              history.update!(published: true, error_message: nil)
            end

            broadcast(job_id, type: 'status', site: display_name(site_name), status: 'success')
          rescue => e
            broadcast(job_id, type: 'log', message: "[#{display_name(site_name)}] ❌ エラー: #{e.message}")
            broadcast(job_id, type: 'status', site: display_name(site_name), status: 'error')
            history.update!(error_message: "#{action_label}失敗: #{e.message}")
          ensure
            context.close rescue nil
          end
        end
      end

      threads.each(&:join)
      browser.close rescue nil
    end

    broadcast(job_id, type: 'log', message: "✅ 全サイト#{action_label}処理完了")
    broadcast(job_id, type: 'done')
  rescue => e
    broadcast(job_id, type: 'error', message: e.message)
    broadcast(job_id, type: 'done')
  end

  private

  def broadcast(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end

  SERVICE_MAP = {
    'kokuchpro'       => Posting::KokuchproService,
    'connpass'        => Posting::ConnpassService,
    'peatix'          => Posting::PeatixService,
    'techplay'        => Posting::TechplayService,
    'tunagate'        => Posting::TunagateService,
    'doorkeeper'      => Posting::DoorkeeperService,
    'street_academy'  => Posting::StreetAcademyService,
    'eventregist'     => Posting::EventregistService,
    'luma'            => Posting::LumaService,
    'seminar_biz'     => Posting::SeminarBizService,
    'twitter'         => Posting::TwitterService,
    'instagram'       => Posting::InstagramService,
    'onclass'         => Posting::OnclassService,
  }.freeze

  DISPLAY_NAMES = {
    'kokuchpro' => 'こくチーズ', 'connpass' => 'connpass', 'peatix' => 'Peatix',
    'techplay' => 'TechPlay', 'tunagate' => 'つなゲート', 'doorkeeper' => 'Doorkeeper',
    'street_academy' => 'ストアカ', 'eventregist' => 'EventRegist', 'luma' => 'Luma',
    'seminar_biz' => 'セミナーBiZ', 'lme' => 'LME', 'jimoty' => 'ジモティー',
    'twitter' => 'X', 'instagram' => 'Instagram', 'onclass' => 'オンクラス',
  }.freeze

  def service_for(site_name)
    klass = SERVICE_MAP[site_name]
    klass&.new
  end

  def display_name(site_name)
    DISPLAY_NAMES[site_name] || site_name
  end

  def find_playwright_path
    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    if File.exist?(local)
      wrapper = '/tmp/playwright-runner.sh'
      File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"\$@\"\n")
      File.chmod(0o755, wrapper)
      return wrapper
    end
    npx = `which npx`.strip
    npx.present? ? "#{npx} playwright" : 'npx playwright'
  end
end
