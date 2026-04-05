require 'playwright'
require 'shellwords'

module Api
  class OnclassController < ApplicationController
    # POST /api/onclass/sync
    # バックグラウンドジョブでオンクラスから受講生を取得
    def sync
      job_id = SecureRandom.hex(8)
      OnclassSyncJob.perform_later(job_id)
      render json: { ok: true, job_id: job_id }
    end

    # GET /api/onclass/students
    # DBから即返却。
    def students
      existing = OnclassStudent.frontend_course.order(:name)
      render json: {
        students: existing.pluck(:name),
        fetchedAt: existing.first&.fetched_at&.iso8601,
        cached: true,
      }
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
  end
end
