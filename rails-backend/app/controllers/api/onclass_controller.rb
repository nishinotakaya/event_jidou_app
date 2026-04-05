require 'playwright'
require 'shellwords'

module Api
  class OnclassController < ApplicationController
    # GET /api/onclass/students
    # DBから即返却。データがなければPlaywrightで取得して保存。
    # ?refresh=true で強制再取得。
    def students
      existing = OnclassStudent.frontend_course.order(:name)

      if existing.any? && params[:refresh] != 'true'
        render json: {
          students: existing.pluck(:name),
          fetchedAt: existing.first.fetched_at&.iso8601,
          cached: true,
        }
        return
      end

      # DB空 or 強制更新 → Playwrightで取得してDB保存
      names = fetch_from_onclass
      save_to_db(names)

      render json: {
        students: names,
        fetchedAt: Time.current.iso8601,
        cached: false,
      }
    rescue => e
      # エラー時でもDBにデータがあればそれを返す
      fallback = OnclassStudent.frontend_course.pluck(:name)
      if fallback.any?
        render json: { students: fallback, cached: true, error: e.message }
      else
        render json: { error: e.message, students: [] }, status: :internal_server_error
      end
    end

    # GET /api/onclass/students_list
    # onclass_studentsテーブルの全レコードを返す
    def students_list
      students = OnclassStudent.order(:course, :name)
      render json: {
        students: students.map { |s|
          { id: s.id, name: s.name, course: s.course, fetchedAt: s.fetched_at&.iso8601 }
        },
        total: students.count,
      }
    end

    # DELETE /api/onclass/students/:id
    # ローカルDBからのみ削除（オンクラスには影響しない）
    def destroy_student
      student = OnclassStudent.find(params[:id])
      student.destroy!
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { error: '受講生が見つかりません' }, status: :not_found
    end

    # POST /api/onclass/sync_sidekiq
    # 外部HerokuアプリのSidekiq cronジョブを一括実行
    def sync_sidekiq
      url = 'https://onclass-lme-jidouka-app-857ffde75fc4.herokuapp.com/sidekiq/cron/namespaces/default/all/enqueue'
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri.path)
      res = http.request(req)

      if res.code.to_i < 400
        render json: { ok: true, message: 'Sidekiqジョブを一括エンキューしました' }
      else
        render json: { ok: false, error: "Sidekiq応答: #{res.code}" }, status: :unprocessable_entity
      end
    rescue => e
      render json: { ok: false, error: e.message }, status: :internal_server_error
    end

    # POST /api/onclass/upload_image
    # 画像を一時保存してパスを返す
    def upload_image
      file = params[:image]
      unless file.is_a?(ActionDispatch::Http::UploadedFile)
        render json: { error: '画像ファイルが必要です' }, status: :bad_request
        return
      end

      ext = File.extname(file.original_filename).presence || '.png'
      filename = "onclass_image_#{Time.now.to_i}#{ext}"
      path = Rails.root.join('tmp', filename).to_s
      File.open(path, 'wb') { |f| f.write(file.read) }

      render json: { path: path, filename: filename }
    end

    private

    def fetch_from_onclass
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
        service.instance_variable_set(:@log_callback, ->(msg) { Rails.logger.info(msg) })

        service.send(:ensure_login, page)
        names = service.send(:fetch_frontend_students, page)

        browser.close
      end

      names
    end

    # ローカル削除した受講生を上書きしない upsert 方式
    def save_to_db(names)
      now = Time.current
      existing = OnclassStudent.where(course: 'フロントエンジニアコース').pluck(:name)
      new_names = names - existing

      OnclassStudent.transaction do
        new_names.each do |name|
          OnclassStudent.create!(name: name, course: 'フロントエンジニアコース', fetched_at: now)
        end
        # 既存レコードの取得日時を更新
        OnclassStudent.where(course: 'フロントエンジニアコース', name: existing & names)
                      .update_all(fetched_at: now)
      end
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
end
