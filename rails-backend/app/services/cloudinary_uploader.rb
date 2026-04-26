require 'net/http'
require 'uri'
require 'json'
require 'digest'
require 'securerandom'

# Cloudinary に画像を Signed Upload する最小実装。
# 認証は環境変数 CLOUDINARY_URL=cloudinary://<api_key>:<api_secret>@<cloud_name> から自動抽出。
class CloudinaryUploader
  class ConfigurationError < StandardError; end
  class UploadError        < StandardError; end

  # @param file [String, IO] バイナリデータ or 開いた IO
  # @param folder [String] Cloudinary 上のフォルダ（例: "host_profile"）
  # @param public_id [String, nil] 上書き用の固定ID（同じID で再 upload すると差し替え）
  # @return [Hash] { 'secure_url' => '...', 'public_id' => '...' } など
  def self.upload(file, folder: nil, public_id: nil)
    new.upload(file, folder: folder, public_id: public_id)
  end

  # 認証情報の解決順:
  #   1) CLOUDINARY_URL=cloudinary://api_key:api_secret@cloud_name (推奨)
  #   2) CLOUDINARY_CLOUD_NAME / CLOUDINARY_API_KEY / CLOUDINARY_API_SECRET の3点セット
  def initialize(url = ENV['CLOUDINARY_URL'])
    if url && !url.to_s.empty?
      parsed = URI.parse(url)
      @api_key    = parsed.user
      @api_secret = parsed.password
      @cloud_name = parsed.host
    else
      @cloud_name = ENV['CLOUDINARY_CLOUD_NAME']
      @api_key    = ENV['CLOUDINARY_API_KEY']
      @api_secret = ENV['CLOUDINARY_API_SECRET']
    end
    missing = { 'cloud_name' => @cloud_name, 'api_key' => @api_key, 'api_secret' => @api_secret }.select { |_, v| v.to_s.empty? }.keys
    unless missing.empty?
      raise ConfigurationError,
        "Cloudinary 認証情報が不足: [#{missing.join(', ')}]。CLOUDINARY_URL を1行設定するか、CLOUDINARY_CLOUD_NAME / CLOUDINARY_API_KEY / CLOUDINARY_API_SECRET を全て設定してください"
    end
  end

  def upload(file, folder: nil, public_id: nil)
    timestamp = Time.now.to_i.to_s

    # 署名対象パラメータ（key の昇順 & API_SECRET 連結 → SHA1）
    sign_params = {}
    sign_params['folder']    = folder    if folder
    sign_params['public_id'] = public_id if public_id
    sign_params['timestamp'] = timestamp
    sign_params['overwrite'] = 'true' if public_id  # 同じ public_id で再アップロードを許可
    sign_params['invalidate'] = 'true' if public_id  # 旧キャッシュを無効化

    signature = Digest::SHA1.hexdigest(sign_params.sort.map { |k, v| "#{k}=#{v}" }.join('&') + @api_secret)

    boundary = "----CloudinaryBoundary#{SecureRandom.hex(8)}"
    body     = build_multipart(file, sign_params.merge('api_key' => @api_key, 'signature' => signature), boundary)

    uri = URI("https://api.cloudinary.com/v1_1/#{@cloud_name}/image/upload")
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    req.body = body

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(req) }
    parsed = JSON.parse(res.body) rescue { 'raw' => res.body }
    unless res.is_a?(Net::HTTPSuccess)
      raise UploadError, "Cloudinary upload failed (#{res.code}): #{parsed.inspect}"
    end
    parsed
  end

  private

  def build_multipart(file, fields, boundary)
    parts = []
    fields.each do |k, v|
      parts << "--#{boundary}\r\n"
      parts << %(Content-Disposition: form-data; name="#{k}"\r\n\r\n)
      parts << "#{v}\r\n"
    end
    binary = file.respond_to?(:read) ? file.read : file.to_s
    parts << "--#{boundary}\r\n"
    parts << %(Content-Disposition: form-data; name="file"; filename="upload.jpg"\r\n)
    parts << "Content-Type: application/octet-stream\r\n\r\n"
    parts << binary
    parts << "\r\n--#{boundary}--\r\n"
    parts.join
  end
end
