module Api
  class PostingHistoriesController < ApplicationController

    # GET /api/posting_histories?item_id=xxx
    def index
      if params[:item_id].present?
        records = PostingHistory.for_item(params[:item_id])
      else
        records = PostingHistory.order(posted_at: :desc).limit(100)
      end
      render json: records.map(&:as_json_safe)
    end

    # GET /api/posting_histories/latest?item_id=xxx
    def latest
      return render(json: []) unless params[:item_id].present?

      # SQLiteではDISTINCT ONが使えないので、Rubyでグルーピング
      records = PostingHistory.where(item_id: params[:item_id]).order(posted_at: :desc)
      latest_per_site = records.group_by(&:site_name).map { |_, v| v.first }
      render json: latest_per_site.map(&:as_json_safe)
    end

    # POST /api/posting_histories/check_participants?item_id=xxx
    def check_participants
      return render(json: { error: 'item_id is required' }, status: :bad_request) unless params[:item_id].present?

      results = ParticipantChecker.check_all(params[:item_id])
      render json: results
    end

    # POST /api/posting_histories/sync?item_id=xxx
    # 1. 既存の投稿履歴URLが生存しているか確認
    # 2. 投稿履歴がないサイトはイベント名で検索して紐付け
    def sync
      return render(json: { error: 'item_id is required' }, status: :bad_request) unless params[:item_id].present?

      # 1. 既存URLの生存確認
      histories = PostingHistory.where(item_id: params[:item_id])
                                .where.not(event_url: [nil, ''])
                                .where.not(status: %w[deleted cancelled])

      histories.each do |h|
        check_event_url(h)
      end

      # 2. 投稿履歴がないサイトを名前で検索して紐付け
      existing_sites = PostingHistory.where(item_id: params[:item_id]).pluck(:site_name).to_set
      connected_sites = ServiceConnection.where(status: 'connected').pluck(:service_name)
      missing_sites = connected_sites.select { |s| !existing_sites.include?(s) && EventSearchService::SITE_CONFIGS.key?(s) }

      if missing_sites.any?
        begin
          searcher = EventSearchService.new(logger: Rails.logger)
          searcher.search_and_sync(params[:item_id])
        rescue => e
          Rails.logger.warn "[EventSearch] #{e.message}"
        end
      end

      records = PostingHistory.where(item_id: params[:item_id]).order(posted_at: :desc)
      latest_per_site = records.group_by(&:site_name).map { |_, v| v.first }
      render json: latest_per_site.map(&:as_json_safe)
    end

    # POST /api/posting_histories/create_manual
    def create_manual
      h = PostingHistory.find_or_initialize_by(item_id: params[:item_id], site_name: params[:site_name])
      h.event_url = params[:event_url]
      h.status = 'success'
      h.published = true
      h.error_message = nil
      h.posted_at = Time.current
      h.save!
      render json: h.as_json_safe
    end

    # PATCH /api/posting_histories/:id/update_url
    def update_url
      h = PostingHistory.find(params[:id])
      h.update!(
        event_url: params[:event_url],
        status: params[:event_url].present? ? 'success' : h.status,
        published: params[:event_url].present? ? true : h.published,
        error_message: nil,
      )
      render json: h.as_json_safe
    end

    # PATCH /api/posting_histories/:id/mark_success
    def mark_success
      h = PostingHistory.find(params[:id])
      h.update!(status: 'success', error_message: nil)
      render json: h.as_json_safe
    end

    # POST /api/posting_histories/bulk_mark_success
    def bulk_mark_success
      scope = PostingHistory.where(status: 'error')
      scope = scope.where(item_id: params[:item_id]) if params[:item_id].present?
      count = scope.update_all(status: 'success', error_message: nil)
      render json: { ok: true, updated: count }
    end

    # POST /api/posting_histories/check_registrations?item_id=xxx
    def check_registrations
      return render(json: { error: 'item_id is required' }, status: :bad_request) unless params[:item_id].present?

      results = RegistrationChecker.check_all(params[:item_id])
      records = PostingHistory.where(item_id: params[:item_id]).order(posted_at: :desc)
      latest_per_site = records.group_by(&:site_name).map { |_, v| v.first }
      render json: latest_per_site.map(&:as_json_safe)
    end

    private

    def check_event_url(h)
      uri = URI(h.event_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 10
      req = Net::HTTP::Head.new(uri.request_uri)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      response = http.request(req)

      code = response.code.to_i
      if code == 404 || code == 410
        h.update!(status: 'not_found', error_message: "HTTP #{code}")
      elsif code >= 500
        Rails.logger.warn "[Sync] #{h.site_name}: HTTP #{code} (サーバーエラー、スキップ)"
      else
        h.update!(error_message: nil) unless h.status == 'not_found'
      end
    rescue => e
      Rails.logger.warn "[Sync] #{h.site_name}: #{e.message}"
    end
  end
end
