module Research
  # サイトごとにスレッドを立てて並列に検索し、成功・失敗・タイムアウトをサイト単位で分離して返す。
  #
  # 呼び出し側は「1サイト分の取得」をブロックで渡すだけでよい（ブロックにはサービスクラスが渡る）。
  # 日付絞り込みなど検索固有の処理は、そのブロックの中で行うこと。
  class ParallelSiteSearch
    Outcome = Struct.new(:results_by_site, :errors_by_site, keyword_init: true)

    # 1サイトの取得を待つ上限。3ページ取得しても実測 1〜3 秒なので、
    # これを超えるのは相手サイトの不調とみなして切り、他サイトの結果だけ返す。
    DEFAULT_TIMEOUT_SECONDS = 25

    TIMEOUT_MESSAGE = "タイムアウトしました".freeze

    # services: { サイト識別子 => サービスクラス }
    # timeout_seconds: 1サイトの取得を待つ上限（省略時は DEFAULT_TIMEOUT_SECONDS）
    # log_prefix: 失敗ログの先頭に付ける文字列（例: "[Research]"）
    def initialize(services:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, log_prefix: "[ParallelSiteSearch]")
      @services = services
      @timeout_seconds = timeout_seconds
      @log_prefix = log_prefix
    end

    def run(site_keys)
      results_by_site = {}
      errors_by_site = {}
      mutex = Mutex.new

      threads = site_keys.map do |site_key|
        Thread.new do
          site_results = yield(@services.fetch(site_key))
          mutex.synchronize { results_by_site[site_key] = site_results }
        rescue StandardError => e
          Rails.logger.warn("#{@log_prefix} #{site_key} の検索に失敗: #{e.class} #{e.message}")
          mutex.synchronize { errors_by_site[site_key] = e.message }
        end
      end
      threads.each { |thread| thread.join(@timeout_seconds) }

      # join がタイムアウトしたスレッドは kill せず放置している（HTTP 待ちで安全に殺せないため）。
      # 放置したスレッドの最長寿命は、1リクエスト最大 OPEN_TIMEOUT 10 秒 + READ_TIMEOUT 20 秒 = 30 秒を
      # MAX_SEARCH_PAGES 3 ページ分で、概算 90 秒（HTTP が終われば自然に終了する）。
      # 生きたまま results_by_site に書き込む可能性があるので、読み出しは必ず mutex 内で行う。
      mutex.synchronize do
        site_keys.each do |site_key|
          next if results_by_site.key?(site_key) || errors_by_site.key?(site_key)

          errors_by_site[site_key] = TIMEOUT_MESSAGE
        end
        Outcome.new(results_by_site: results_by_site.dup, errors_by_site: errors_by_site.dup)
      end
    end
  end
end
