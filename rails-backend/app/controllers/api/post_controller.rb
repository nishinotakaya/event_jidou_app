require 'open3'
require 'json'

module Api
  class PostController < ApplicationController
    # SSE で投稿進捗を配信（Node.js の投稿スクリプトを子プロセスで呼び出す）
    def create
      content     = params[:content]
      sites       = params[:sites] || []
      event_fields = params[:eventFields]&.to_unsafe_h || {}
      generate_image = params[:generateImage]
      image_style  = params[:imageStyle]
      openai_api_key = params[:openaiApiKey].presence || ENV['OPENAI_API_KEY']

      response.headers['Content-Type']  = 'text/event-stream'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['Connection']    = 'keep-alive'
      response.headers['X-Accel-Buffering'] = 'no'

      send_event = ->(data) { response.stream.write("data: #{data.to_json}\n\n") }

      if sites.empty?
        send_event.call(type: 'error', message: '投稿先が選択されていません')
        return response.stream.close
      end

      # Node.js の投稿処理を呼び出すためのペイロードを一時ファイルに保存
      payload = {
        content: content,
        sites: sites,
        eventFields: event_fields,
        generateImage: generate_image,
        imageStyle: image_style,
        openaiApiKey: openai_api_key,
      }

      node_root = File.expand_path('../../../../..', __dir__)
      payload_file = Rails.root.join('tmp', "post_payload_#{SecureRandom.hex(8)}.json")
      File.write(payload_file, payload.to_json)

      begin
        node_script = File.join(node_root, 'scripts', 'rails-post-bridge.js')
        env = { 'NODE_NO_WARNINGS' => '1' }
        Open3.popen3(env, 'node', node_script, payload_file.to_s, chdir: node_root) do |_stdin, stdout, stderr, thread|
          stdout.each_line do |line|
            line.strip!
            next if line.empty?
            begin
              data = JSON.parse(line)
              send_event.call(data)
            rescue JSON::ParserError
              send_event.call(type: 'log', message: line)
            end
          end
          thread.value
        end
      rescue => e
        send_event.call(type: 'error', message: e.message)
      ensure
        File.delete(payload_file) if File.exist?(payload_file)
        send_event.call(type: 'done')
        response.stream.close
      end
    end
  end
end
