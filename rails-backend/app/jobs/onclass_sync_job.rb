require 'playwright'
require 'shellwords'

class OnclassSyncJob < ApplicationJob
  queue_as :default

  def perform(job_id)
    broadcast(job_id, type: 'log', message: 'オンクラスから受講生データを取得中...')

    playwright_path = find_playwright_path
    names = []

    Playwright.create(playwright_cli_executable_path: playwright_path) do |pw|
      browser = pw.chromium.launch(
        headless: false,
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
      )
      context = browser.new_context(
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      )
      page = context.new_page

      service = Posting::OnclassService.new
      service.instance_variable_set(:@log_callback, ->(msg) {
        Rails.logger.info(msg)
        broadcast(job_id, type: 'log', message: msg)
      })

      broadcast(job_id, type: 'log', message: 'オンクラスにログイン中...')
      service.send(:ensure_login, page)

      broadcast(job_id, type: 'log', message: '受講生一覧を取得中...')
      names = service.send(:fetch_frontend_students, page)

      browser.close
    end

    save_to_db(names)

    broadcast(job_id, type: 'done', message: "#{names.length}名の受講生を同期しました", count: names.length)
  rescue => e
    Rails.logger.error("OnclassSyncJob error: #{e.message}")
    broadcast(job_id, type: 'error', message: "同期エラー: #{e.message}")
  end

  private

  def save_to_db(names)
    now = Time.current
    existing = OnclassStudent.where(course: 'フロントエンジニアコース').pluck(:name)
    new_names = names - existing

    OnclassStudent.transaction do
      new_names.each do |name|
        OnclassStudent.create!(name: name, course: 'フロントエンジニアコース', fetched_at: now)
      end
      OnclassStudent.where(course: 'フロントエンジニアコース', name: existing & names)
                    .update_all(fetched_at: now)
    end
  end

  def broadcast(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end

  def find_playwright_path
    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    if File.exist?(local)
      wrapper = '/tmp/playwright-runner.sh'
      unless File.exist?(wrapper)
        File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
        File.chmod(0o755, wrapper)
      end
      return wrapper
    end
    npx = `which npx`.strip
    npx.present? ? "#{npx} playwright" : 'npx playwright'
  end
end
