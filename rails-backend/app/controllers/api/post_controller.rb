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
  end
end
