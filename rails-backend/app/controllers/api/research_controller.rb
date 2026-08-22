module Api
  # 複数のイベントサイトを横断してキーワード検索する（交流会リサーチ）。
  #
  # ■ 全体の流れ
  #   1. 選択されたサイトごとにスレッドを立てて並列取得する（直列だと 8 サイト × 1〜3 秒で待たされるため）
  #   2. 取得結果は必ず Research::DateRange#filter を通す（終了したイベントを出さないため）
  #   3. 失敗したサイトは他サイトの結果を巻き添えにせず、errors に理由を入れて返す
  #   4. サーバーのIPを弾くサイト（Peatix）は browserFallbacks を返し、ブラウザ側から取り直してもらう
  #
  # ■ サイトを追加するときは
  #   - Research::BaseService を継承したサービスを作り、下の SERVICES に登録する
  #   - フロントの ResearchPage.jsx の SITES にも同じキーで追加する（ラベル・色はフロント側の責務）
  class ResearchController < ApplicationController
    # キーは API のリクエスト/レスポンス両方で使うサイト識別子。フロントの SITES と一対一で対応させる。
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

    # 1サイトの取得を待つ上限。3ページ取得しても実測 1〜3 秒なので、
    # これを超えるのは相手サイトの不調とみなして切り、他サイトの結果だけ返す。
    SITE_TIMEOUT_SECONDS = 25

    # ブラウザからサイトのAPIを直接叩くときに付けるヘッダ（Peatix は X-Requested-With が無いと HTML を返す）
    BROWSER_FALLBACK_HEADERS = { "X-Requested-With" => "XMLHttpRequest", "Accept" => "application/json" }.freeze

    def search
      keyword = params[:keyword].to_s.strip
      if keyword.empty?
        return render json: { error: "キーワードを入力してください" }, status: :unprocessable_entity
      end

      site_keys = Array(params[:sites]).map(&:to_s) & SERVICES.keys
      site_keys = SERVICES.keys if site_keys.empty?
      locations = Array(params[:locations]).map(&:to_s) & Research::BaseService::LOCATION_ALIASES.keys
      date_range = requested_date_range

      results_by_site = {}
      errors_by_site = {}
      mutex = Mutex.new

      threads = site_keys.map do |site_key|
        Thread.new do
          site_results = SERVICES[site_key].new(date_range).search(keyword, locations)
          mutex.synchronize { results_by_site[site_key] = date_range.filter(site_results) }
        rescue StandardError => e
          Rails.logger.warn("[Research] #{site_key} の検索に失敗: #{e.class} #{e.message}")
          mutex.synchronize { errors_by_site[site_key] = e.message }
        end
      end
      threads.each { |thread| thread.join(SITE_TIMEOUT_SECONDS) }

      # join がタイムアウトしたスレッドは kill せず放置している（HTTP 待ちで安全に殺せないため）。
      # 生きたまま results_by_site に書き込む可能性があるので、読み出しは必ず mutex 内で行う。
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
        searchedDateFrom: date_range.from_param,
        searchedDateTo: date_range.to_param,
        countsBySite: results_snapshot.transform_values(&:size),
        browserFallbacks: browser_fallbacks_for(errors_by_site.keys, keyword)
      }
    end

    # ブラウザが直接取得したレスポンス本文を、サーバー側と同じロジックで整形して返す。
    # Peatix のようにデータセンターIP（Heroku）を弾くサイト向けの逃げ道で、
    # 「取得はユーザーの回線・整形はサーバー」に分けることで、整形ロジックの二重実装を避けている。
    # 対応できるのは parse_response を実装したサービスだけ（＝レスポンス本文だけで完結するAPI型のサイト）。
    def normalize
      service_class = SERVICES[params[:site].to_s]
      unless service_class&.method_defined?(:parse_response)
        return render json: { error: "このサイトはブラウザ取得に対応していません" }, status: :unprocessable_entity
      end

      locations = Array(params[:locations]).map(&:to_s) & Research::BaseService::LOCATION_ALIASES.keys
      date_range = requested_date_range
      results = service_class.new(date_range).parse_response(params[:payload].to_s, locations)
      render json: { results: date_range.filter(results) }
    rescue StandardError => e
      Rails.logger.warn("[Research] #{params[:site]} のブラウザ取得結果の整形に失敗: #{e.class} #{e.message}")
      render json: { error: "取得結果を読み取れませんでした（#{e.message}）" }, status: :unprocessable_entity
    end

    private

    # 開催日の絞り込み条件。未指定でも「今日以降」になるので、終了したイベントは常に落ちる。
    def requested_date_range
      Research::DateRange.new(from: params[:dateFrom], to: params[:dateTo])
    end

    # 失敗したサイトのうち、ブラウザから直接叩ける（CORS許可済みの）APIを持つものだけを返す。
    # 現状の該当は Peatix のみ。TechPlay も同じくIPで弾かれるが、HTML スクレイプで CORS が無いため救えない。
    def browser_fallbacks_for(failed_site_keys, keyword)
      failed_site_keys.each_with_object({}) do |site_key, fallbacks|
        service_class = SERVICES[site_key]
        next unless service_class.respond_to?(:search_api_urls)

        fallbacks[site_key] = { urls: service_class.search_api_urls(keyword), headers: BROWSER_FALLBACK_HEADERS }
      end
    end
  end
end
