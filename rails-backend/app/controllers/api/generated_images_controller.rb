module Api
  class GeneratedImagesController < ApplicationController
    # GET /api/generated_images
    def index
      scope = GeneratedImage.recent.limit(200)
      scope = scope.where(user_id: current_user.id) if current_user
      render json: scope.map(&:as_json_safe)
    end

    # GET /api/generated_images/:id  (バイナリ配信)
    def show
      img = GeneratedImage.find(params[:id])
      send_data img.data,
                type: img.content_type.presence || 'image/png',
                disposition: 'inline',
                filename: img.filename.presence || "image_#{img.id}.png"
    end

    # POST /api/generated_images  (アップロード保存)
    def create
      file = params[:image]
      unless file.is_a?(ActionDispatch::Http::UploadedFile)
        render json: { error: '画像ファイルが必要です' }, status: :bad_request
        return
      end

      bytes = file.read
      img = GeneratedImage.create!(
        user_id: current_user&.id,
        source: 'upload',
        filename: file.original_filename,
        content_type: file.content_type.presence || 'image/png',
        byte_size: bytes.bytesize,
        data: bytes,
      )
      render json: img.as_json_safe
    end

    # DELETE /api/generated_images/:id
    def destroy
      img = GeneratedImage.find(params[:id])
      img.destroy!
      render json: { ok: true }
    end
  end
end
