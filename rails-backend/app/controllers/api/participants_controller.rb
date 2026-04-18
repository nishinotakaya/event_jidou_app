module Api
  class ParticipantsController < ApplicationController
    # GET /api/participants?item_id=xxx
    def index
      return render(json: { error: 'item_id required' }, status: :bad_request) unless params[:item_id].present?
      participants = EventParticipant.for_item(params[:item_id])
      by_site = participants.group_by(&:site_name).transform_values { |list| list.map(&:as_json_safe) }
      render json: { participants: by_site, total: participants.count }
    end

    # POST /api/participants/sync?item_id=xxx
    # 各サイトAPIから参加者を取得してDBに保存
    def sync
      return render(json: { error: 'item_id required' }, status: :bad_request) unless params[:item_id].present?
      item_id = params[:item_id]

      results = {}

      # Peatix: API経由（Playwright不要）
      peatix_history = PostingHistory.find_by(item_id: item_id, site_name: 'peatix', status: 'success')
      if peatix_history&.event_url.present?
        participants = ParticipantChecker.extract_peatix_participants_api(peatix_history.event_url)
        save_participants(item_id, 'peatix', participants)
        results['peatix'] = participants.length
      end

      # connpass: 公開ページから参加者数取得（名前はAPI非公開）
      connpass_history = PostingHistory.find_by(item_id: item_id, site_name: 'connpass', status: 'success')
      if connpass_history&.event_url.present?
        count = RegistrationChecker.check_connpass(connpass_history.event_url)
        results['connpass'] = count || 0
      end

      # Doorkeeper: API経由
      dk_history = PostingHistory.find_by(item_id: item_id, site_name: 'doorkeeper', status: 'success')
      if dk_history&.event_url.present?
        count = RegistrationChecker.check_doorkeeper(dk_history.event_url)
        results['doorkeeper'] = count || 0
      end

      # TechPlay: 公開ページJSON経由
      tp_history = PostingHistory.find_by(item_id: item_id, site_name: 'techplay', status: 'success')
      if tp_history&.event_url.present?
        count = RegistrationChecker.check_techplay(tp_history.event_url)
        results['techplay'] = count || 0
      end

      # 申し込み数もDBに反映
      results.each do |site, count|
        h = PostingHistory.find_by(item_id: item_id, site_name: site)
        h&.update!(registrations: count.is_a?(Integer) ? count : (count || 0), registrations_checked_at: Time.current)
      end

      by_site = EventParticipant.for_item(item_id).group_by(&:site_name).transform_values { |list| list.map(&:as_json_safe) }
      render json: { participants: by_site, counts: results, total: EventParticipant.where(item_id: item_id).count }
    end

    private

    def save_participants(item_id, site_name, participants)
      EventParticipant.where(item_id: item_id, site_name: site_name).delete_all
      participants.each do |p|
        EventParticipant.create!(
          item_id: item_id,
          site_name: site_name,
          name: p['name'].to_s.presence,
          email: p['email'].to_s.presence,
        )
      end
    end
  end
end
