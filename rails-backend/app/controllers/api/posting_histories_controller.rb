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

    private

    def check_event_url(h)
      uri = URI(h.event_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 10
      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      response = http.request(req)

      code = response.code.to_i
      if code == 403
        # 403はログインが必要なだけでイベントは存在する可能性が高い（connpass, こくチーズ等）
        h.update!(status: h.published? ? 'success' : 'draft', error_message: nil)
      elsif code == 502 || code == 503
        # 一時的なサーバーエラーはステータスを変更しない
        Rails.logger.warn "[Sync] #{h.site_name}: HTTP #{code} (一時エラー、スキップ)"
      elsif code >= 400
        h.update!(status: 'not_found', error_message: "HTTP #{code}")
      else
        body = response.body.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        not_found_patterns = [
          'ページが見つかりません', 'ページが見つかりませんでした',
          'お探しのページは見つかりませんでした', 'このページは存在しません',
          'Page Not Found', 'Not Found',
        ]
        ended_patterns = [
          'このイベントは終了しました', 'イベントは終了しました',
          '受付終了', 'このイベントは中止されました',
        ]

        if not_found_patterns.any? { |p| body.include?(p) }
          h.update!(status: 'not_found', error_message: 'ページが見つかりません')
        elsif ended_patterns.any? { |p| body.include?(p) }
          h.update!(status: 'ended', error_message: 'イベント終了')
        else
          h.update!(status: h.published? ? 'success' : 'draft', error_message: nil)
        end
      end
    rescue => e
      h.update!(status: 'error', error_message: "同期エラー: #{e.message}")
    end

    # POST /api/posting_histories/check_registrations?item_id=xxx
    def check_registrations
      return render(json: { error: 'item_id is required' }, status: :bad_request) unless params[:item_id].present?

      results = RegistrationChecker.check_all(params[:item_id])
      # 更新後の最新データを返す
      records = PostingHistory.where(item_id: params[:item_id]).order(posted_at: :desc)
      latest_per_site = records.group_by(&:site_name).map { |_, v| v.first }
      render json: latest_per_site.map(&:as_json_safe)
    end
  end
end
