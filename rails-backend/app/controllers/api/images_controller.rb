module Api
  class ImagesController < ApplicationController
    # POST /api/upload_image
    # 画像をpublic/uploads/に保存し、URLを返す
    def upload
      file = params[:image]
      unless file.is_a?(ActionDispatch::Http::UploadedFile)
        render json: { error: '画像ファイルが必要です' }, status: :bad_request
        return
      end

      upload_dir = Rails.root.join('public', 'uploads')
      FileUtils.mkdir_p(upload_dir)

      ext = File.extname(file.original_filename).presence || '.png'
      filename = "img_#{Time.now.to_i}_#{SecureRandom.hex(4)}#{ext}"
      path = upload_dir.join(filename).to_s
      File.open(path, 'wb') { |f| f.write(file.read) }

      url = "/uploads/#{filename}"
      render json: { url: url, filename: filename, path: path }
    end
  end
end
