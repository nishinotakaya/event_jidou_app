module Api
  class XController < ApplicationController
    before_action :authenticate_user!, except: []

    # GET /api/x/posts?from=YYYY-MM-DD&to=YYYY-MM-DD
    def posts
      from = parse_date(params[:from]) || 1.month.ago.beginning_of_day
      to   = parse_date(params[:to])&.end_of_day || 2.months.from_now.end_of_day
      list = current_user.x_posts.where(scheduled_at: from..to).order(:scheduled_at).map { |p| serialize(p) }
      render json: { posts: list }
    end

    # POST /api/x/posts  body: { content, scheduled_at, image_url? }
    def create_post
      post = current_user.x_posts.new(
        content: params[:content].to_s,
        scheduled_at: parse_time(params[:scheduled_at]) || 10.minutes.from_now,
        image_url: params[:image_url],
        source: params[:source].presence || 'manual',
        item_id: params[:item_id],
      )
      if post.save
        render json: { post: serialize(post) }
      else
        render json: { error: post.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # PUT /api/x/posts/:id
    def update_post
      post = current_user.x_posts.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless post

      attrs = {}
      attrs[:content]      = params[:content]      if params.key?(:content)
      attrs[:scheduled_at] = parse_time(params[:scheduled_at]) if params.key?(:scheduled_at)
      attrs[:image_url]    = params[:image_url]    if params.key?(:image_url)
      if post.update(attrs)
        render json: { post: serialize(post) }
      else
        render json: { error: post.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # DELETE /api/x/posts/:id
    def destroy_post
      post = current_user.x_posts.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless post
      post.destroy!
      render json: { ok: true }
    end

    # POST /api/x/posts/:id/post_now → その場で同期投稿
    # 失敗投稿の「再投稿」もここを通る。Sidekiq に依存せず、X API を直接叩いて
    # 成功/失敗をその場でフロントへ返す。投稿済みは二重投稿防止のため弾く。
    def post_now
      post = current_user.x_posts.find_by(id: params[:id])
      return render json: { error: 'not found' }, status: :not_found unless post
      return render json: { error: 'すでに投稿済みです' }, status: :unprocessable_entity if post.status == 'posted'

      post.update!(scheduled_at: Time.current)
      result = X::Publisher.new(post).call
      if result.ok?
        render json: { ok: true, post: serialize(post.reload) }
      else
        connected = ServiceConnection.where(user_id: current_user.id, service_name: 'x').where.not(session_data: [nil, '']).exists?
        render json: { ok: false, error: result.error, needs_connect: !connected, post: serialize(post.reload) }, status: :unprocessable_entity
      end
    end

    # POST /api/x/generate_month
    # body: { extra_theme?, start_date?, days?, per_day?, time_slots?, dry_run?, apiKey? }
    # 同期では OpenAI 呼び出し (30〜60s) が Heroku ルーター 30s 制限を超えるため、
    # Sidekiq に投げて ActionCable で進捗を通知する。
    def generate_month
      job_id = SecureRandom.hex(8)
      payload = params.permit(:extra_theme, :start_date, :per_day, :days, :dry_run, :apiKey, time_slots: []).to_h
      XGenerateMonthJob.perform_later(job_id, current_user.id, payload)
      render json: { job_id: job_id }
    end

    # POST /api/x/connect  body: { auth_token, ct0 }
    def connect
      session_payload = { auth_token: params[:auth_token].to_s.strip, ct0: params[:ct0].to_s.strip }
      if session_payload[:auth_token].empty? || session_payload[:ct0].empty?
        return render json: { error: 'auth_token と ct0 が必要です' }, status: :unprocessable_entity
      end

      # 疎通確認
      result = X::Client.new(session_payload).verify
      unless result[:ok]
        return render json: { error: "X 認証失敗: #{result[:error] || result[:status]}" }, status: :unprocessable_entity
      end

      conn = ServiceConnection.find_or_initialize_by(user_id: current_user.id, service_name: 'x')
      conn.session_data = session_payload.to_json
      conn.status = 'connected'
      conn.last_connected_at = Time.current
      conn.error_message = nil
      conn.save!
      render json: { ok: true, screen_name: result[:screen_name], id: result[:id], name: result[:name] }
    end

    # POST /api/x/test
    def test
      conn = ServiceConnection.find_by(user_id: current_user.id, service_name: 'x')
      return render json: { ok: false, error: '未接続' }, status: :ok if conn.nil? || conn.session_data.blank?

      result = X::Client.new(conn.session_data).verify
      if result[:ok]
        conn.update(status: 'connected', last_connected_at: Time.current, error_message: nil)
        render json: { ok: true, screen_name: result[:screen_name] }
      else
        conn.update(status: 'error', error_message: result[:error].to_s[0, 500])
        render json: { ok: false, error: result[:error] || result[:status] }
      end
    end

    # GET /api/x/status
    def status
      conn = ServiceConnection.find_by(user_id: current_user.id, service_name: 'x')
      render json: {
        connected: conn&.status == 'connected',
        screen_name: nil, # verify を毎回叩かない
        last_connected_at: conn&.last_connected_at,
        pending_count: current_user.x_posts.pending.count,
        posted_count:  current_user.x_posts.posted.count,
        failed_count:  current_user.x_posts.failed.count,
      }
    end

    private

    def serialize(p)
      {
        id: p.id, content: p.content, image_url: p.image_url,
        scheduled_at: p.scheduled_at, status: p.status,
        posted_at: p.posted_at, tweet_url: p.tweet_url,
        error_message: p.error_message, source: p.source, item_id: p.item_id,
      }
    end

    def parse_date(s) = (Date.parse(s.to_s) rescue nil)
    def parse_time(s) = (Time.zone.parse(s.to_s) rescue nil)
  end
end
