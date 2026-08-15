module Api
  # 複数のイベントサイトを横断してキーワード検索する（交流会リサーチ）。
  class ResearchController < ApplicationController
    SERVICES = {
      "kokuchpro" => Research::KokuchproService,
      "peatix" => Research::PeatixService,
      "connpass" => Research::ConnpassService,
      "techplay" => Research::TechplayService,
      "doorkeeper" => Research::DoorkeeperService,
      "jimoty" => Research::JimotyService,
      "evenz" => Research::EvenzService,
      "doomo" => Research::DoomoService
    }.freeze

    SITE_TIMEOUT_SECONDS = 25

    # ブラウザからサイトのAPIを直接叩くときに付けるヘッダ
    BROWSER_FALLBACK_HEADERS = { "X-Requested-With" => "XMLHttpRequest", "Accept" => "application/json" }.freeze

    def search
      keyword = params[:keyword].to_s.strip
      if keyword.empty?
        return render json: { error: "キーワードを入力してください" }, status: :unprocessable_entity
      end

      site_keys = Array(params[:sites]).map(&:to_s) & SERVICES.keys
      site_keys = SERVICES.keys if site_keys.empty?
      locations = Array(params[:locations]).map(&:to_s) & Research::BaseService::LOCATION_ALIASES.keys

      results_by_site = {}
      errors_by_site = {}
      mutex = Mutex.new

      threads = site_keys.map do |site_key|
        Thread.new do
          site_results = SERVICES[site_key].new.search(keyword, locations)
          mutex.synchronize { results_by_site[site_key] = site_results }
        rescue StandardError => e
          Rails.logger.warn("[Research] #{site_key} の検索に失敗: #{e.class} #{e.message}")
          mutex.synchronize { errors_by_site[site_key] = e.message }
        end
      end
      threads.each { |thread| thread.join(SITE_TIMEOUT_SECONDS) }

      # タイムアウトしたスレッドはまだ書き込み得るので、スナップショットも mutex 内で取る
      mutex.synchronize do
        site_keys.each do |site_key|
          next if results_by_site.key?(site_key) || errors_by_site.key?(site_key)

          errors_by_site[site_key] = "タイムアウトしました"
        end
      end

      results_snapshot = mutex.synchronize { results_by_site.dup }
      merged_results = results_snapshot.values.flatten
                                       .sort_by { |result| result[:startsAt] || "9999-12-31" }

      render json: {
        results: merged_results,
        errors: errors_by_site,
        searchedSites: site_keys,
        searchedLocations: locations,
        countsBySite: results_snapshot.transform_values(&:size),
        browserFallbacks: browser_fallbacks_for(errors_by_site.keys, keyword)
      }
    end

    # ブラウザが直接取得したレスポンス本文を、サーバ側と同じロジックで整形して返す。
    # Peatix のようにデータセンターIP（Heroku）を弾くサイト向けの逃げ道。
    def normalize
      service_class = SERVICES[params[:site].to_s]
      unless service_class&.method_defined?(:parse_response)
        return render json: { error: "このサイトはブラウザ取得に対応していません" }, status: :unprocessable_entity
      end

      locations = Array(params[:locations]).map(&:to_s) & Research::BaseService::LOCATION_ALIASES.keys
      render json: { results: service_class.new.parse_response(params[:payload].to_s, locations) }
    rescue StandardError => e
      Rails.logger.warn("[Research] #{params[:site]} のブラウザ取得結果の整形に失敗: #{e.class} #{e.message}")
      render json: { error: "取得結果を読み取れませんでした（#{e.message}）" }, status: :unprocessable_entity
    end

    private

    # データセンターIPを弾かれて失敗したサイトのうち、ブラウザから直接叩ける（CORS許可済みの）APIを持つものを返す。
    def browser_fallbacks_for(failed_site_keys, keyword)
      failed_site_keys.each_with_object({}) do |site_key, fallbacks|
        service_class = SERVICES[site_key]
        next unless service_class.respond_to?(:search_api_urls)

        fallbacks[site_key] = { urls: service_class.search_api_urls(keyword), headers: BROWSER_FALLBACK_HEADERS }
      end
    end
  end
end
