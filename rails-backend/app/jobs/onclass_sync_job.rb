# オンクラスからフロントエンジニアコース受講生を取得して DB へ同期する（API 直叩き・Playwright 不要）
class OnclassSyncJob < ApplicationJob
  queue_as :default

  FRONTEND_COURSE_NAME = "フロントエンジニアコース".freeze

  def perform(job_id)
    broadcast(job_id, type: "log", message: "オンクラスから受講生データを取得中...")

    client = OnclassApiClient.from_service_connection(logger: Rails.logger)
    client.sign_in!
    broadcast(job_id, type: "log", message: "オンクラスにログインしました（API）")

    course = client.learning_courses.find { |c| c["name"] == FRONTEND_COURSE_NAME }
    raise "講座「#{FRONTEND_COURSE_NAME}」が見つかりません" unless course

    students = client.users(learning_course_id: course["id"])
    names = students.map { |s| s["name"].to_s.strip }.reject(&:empty?).uniq
    broadcast(job_id, type: "log", message: "受講生一覧を取得しました（#{names.length}名）")

    save_to_db(names)

    broadcast(job_id, type: "done", message: "#{names.length}名の受講生を同期しました", count: names.length)
  rescue => e
    Rails.logger.error("OnclassSyncJob error: #{e.message}")
    broadcast(job_id, type: "error", message: "同期エラー: #{e.message}")
  end

  private

  def save_to_db(names)
    now = Time.current
    existing = OnclassStudent.where(course: FRONTEND_COURSE_NAME).pluck(:name)
    new_names = names - existing

    OnclassStudent.transaction do
      new_names.each do |name|
        OnclassStudent.create!(name: name, course: FRONTEND_COURSE_NAME, fetched_at: now)
      end
      OnclassStudent.where(course: FRONTEND_COURSE_NAME, name: existing & names)
                    .update_all(fetched_at: now)
    end
  end

  def broadcast(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end
end
