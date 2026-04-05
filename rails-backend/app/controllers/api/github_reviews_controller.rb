module Api
  class GithubReviewsController < ApplicationController
    before_action :require_user

    # GET /api/github_reviews — レビュー一覧
    def index
      reviews = GithubReview.order(created_at: :desc).limit(params[:limit] || 50)
      reviews = reviews.where(status: params[:status]) if params[:status].present?
      render json: reviews.as_json(except: [:updated_at])
    end

    # GET /api/github_reviews/:id
    def show
      review = GithubReview.find(params[:id])
      render json: review.as_json
    end

    # PUT /api/github_reviews/:id — レビュー内容を編集
    def update
      review = GithubReview.find(params[:id])
      review.update!(review_params)
      render json: review.as_json
    end

    # POST /api/github_reviews/:id/approve — レビュー承認
    def approve
      review = GithubReview.find(params[:id])
      review.update!(status: 'approved')
      render json: { ok: true, status: review.status }
    end

    # POST /api/github_reviews/:id/post_to_github — GitHubにコメント投稿 + オンクラス通知
    def post_to_github
      review = GithubReview.find(params[:id])
      raise 'レビューが承認されていません' unless review.status == 'approved'

      service = GithubReviewService.new
      comment_body = params[:comment] || review.review_content
      result = service.post_comment(review.github_url, comment_body)

      review.update!(
        status: 'posted',
        github_comment_url: result['html_url'],
        posted_at: Time.current,
      )

      # オンクラスのコミュニティにレビュー完了通知を送信
      OnclassReviewNotifyJob.perform_later(review.id)

      render json: { ok: true, comment_url: result['html_url'] }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/github_reviews/:id/re_review — 再レビュー
    def re_review
      review = GithubReview.find(params[:id])
      job_id = "re_review_#{SecureRandom.hex(8)}"
      review.update!(status: 'pending')
      GithubReReviewJob.perform_later(job_id, review.id)
      render json: { ok: true, job_id: job_id }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/github_reviews/scan — 手動スキャン実行（ActionCable対応）
    def scan
      job_id = "github_scan_#{SecureRandom.hex(8)}"
      GithubReviewScanJob.perform_later(job_id)
      render json: { ok: true, job_id: job_id, message: 'スキャンジョブを開始しました' }
    end

    # POST /api/github_reviews/:id/open_local — ローカルリポジトリをVS Codeで開く
    def open_local
      review = GithubReview.find(params[:id])
      service = LocalRepoService.new
      result = service.setup_and_open(review.github_url, author_name: review.author)
      render json: { ok: true, path: result[:path], action: result[:action], app_started: result[:app_started] }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def require_user
      unless current_user
        render json: { error: 'ログインが必要です' }, status: :unauthorized
      end
    end

    def review_params
      params.permit(:review_content, :status)
    end
  end
end
