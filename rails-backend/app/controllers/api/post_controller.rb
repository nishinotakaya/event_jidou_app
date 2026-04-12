module Api
  class PostController < ApplicationController
    # Enqueue a background PostJob and return job_id for ActionCable subscription
    def create
      job_id = SecureRandom.hex(8)

      payload = {
        'content'      => params[:content].to_s,
        'sites'        => Array(params[:sites]),
        'eventFields'  => params[:eventFields]&.to_unsafe_h || {},
        'generateImage' => params[:generateImage],
        'imageStyle'   => params[:imageStyle],
        'openaiApiKey' => params[:openaiApiKey].presence || ENV['OPENAI_API_KEY'],
        'dalleApiKey'  => params[:dalleApiKey].presence,
        'itemId'       => params[:itemId].to_s,
      }

      if payload['sites'].empty?
        return render json: { error: '投稿先が選択されていません' }, status: :unprocessable_entity
      end

      payload['userId'] = current_user.id
      PostJob.perform_later(job_id, payload)

      render json: { job_id: job_id }
    end

    # リモートイベント削除
    def delete_remote
      job_id  = SecureRandom.hex(8)
      item_id = params[:item_id].to_s
      return render json: { error: 'item_id is required' }, status: :unprocessable_entity if item_id.blank?

      RemoteActionJob.perform_later(job_id, item_id, 'delete')
      render json: { job_id: job_id }
    end

    # リモートイベント中止
    def cancel_remote
      job_id  = SecureRandom.hex(8)
      item_id = params[:item_id].to_s
      return render json: { error: 'item_id is required' }, status: :unprocessable_entity if item_id.blank?

      RemoteActionJob.perform_later(job_id, item_id, 'cancel')
      render json: { job_id: job_id }
    end

    # 全サイト一括公開
    def publish_all
      job_id  = SecureRandom.hex(8)
      item_id = params[:item_id].to_s
      return render json: { error: 'item_id is required' }, status: :unprocessable_entity if item_id.blank?

      RemoteActionJob.perform_later(job_id, item_id, 'publish')
      render json: { job_id: job_id }
    end

    # ❌ エラーサイトだけ再投稿
    def retry_errors
      item_id = params[:item_id].to_s
      return render json: { error: 'item_id is required' }, status: :unprocessable_entity if item_id.blank?

      item = Item.find_by(id: item_id)
      return render json: { error: 'イベントが見つかりません' }, status: :not_found unless item

      # ❌ エラー/not_found + 📝 未公開(success but not published) を対象
      error_histories = PostingHistory.where(item_id: item_id).where(
        'status IN (?) OR (status = ? AND published = ?)', %w[error not_found], 'success', false
      )
      if error_histories.empty?
        return render json: { error: '再投稿対象のサイトがありません' }, status: :unprocessable_entity
      end

      service_to_site = PostJob::SITE_TO_SERVICE.invert
      sites = error_histories.map { |h| service_to_site[h.site_name] }.compact

      if sites.empty?
        return render json: { error: '再投稿対象サイトがありません' }, status: :unprocessable_entity
      end

      # ストアカが含まれる場合は画像自動生成ON
      needs_image = sites.include?('ストアカ')

      job_id = SecureRandom.hex(8)
      payload = {
        'content'      => item.content.to_s,
        'sites'        => sites,
        'eventFields'  => {
          'title'      => item.name,
          'startDate'  => item.event_date,
          'startTime'  => item.event_time,
          'endTime'    => item.event_end_time,
          'zoomUrl'    => item.zoom_url,
          'publishSites' => sites.each_with_object({}) { |s, h| h[s] = true },
        },
        'generateImage' => needs_image,
        'imageStyle'   => 'cute',
        'openaiApiKey' => AppSetting.get('openai_api_key').presence || ENV['OPENAI_API_KEY'],
        'dalleApiKey'  => AppSetting.get('dalle_api_key').presence || ENV['OPENAI_API_KEY'],
        'itemId'       => item_id,
        'userId'       => current_user.id,
      }

      PostJob.perform_later(job_id, payload)
      render json: { job_id: job_id, sites: sites }
    end
  end
end
