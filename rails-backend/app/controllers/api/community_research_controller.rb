module Api
  # 交流会・コミュニティ（オンラインサロン、メンバー募集、倫理法人会など）を横断してキーワード検索する。
  # イベント検索（ResearchController）との違いは、開催日の概念が無いので日付で絞らず並べ替えもしない点。
  #
  # サイトを追加するときは Research::Communities::BaseService を継承したサービスを作り、下の SERVICES に登録する。
  class CommunityResearchController < ApplicationController
    # キーは API のリクエスト/レスポンス両方で使うサイト識別子。results はこの登録順で並べる。
    SERVICES = {
      "jimoty_member" => Research::Communities::JimotyMemberService,
      "dmm_salon" => Research::Communities::DmmSalonService,
      "campfire" => Research::Communities::CampfireService,
      "meetup_group" => Research::Communities::MeetupGroupService,
      "rinri" => Research::Communities::RinriService,
      "yeg" => Research::Communities::YegService
    }.freeze

    # 1サイトの取得を待つ上限。これを超えるのは相手サイトの不調とみなして切り、他サイトの結果だけ返す。
    SITE_TIMEOUT_SECONDS = 25

    def search
      keyword = params[:keyword].to_s.strip
      if keyword.empty?
        return render json: { error: "キーワードを入力してください" }, status: :unprocessable_entity
      end

      site_keys = Array(params[:sites]).map(&:to_s) & SERVICES.keys
      site_keys = SERVICES.keys if site_keys.empty?
      locations = Array(params[:locations]).map(&:to_s) & Research::BaseService::LOCATION_ALIASES.keys

      outcome = parallel_search.run(site_keys) { |service_class| service_class.new.search(keyword, locations) }

      render json: {
        results: SERVICES.keys.flat_map { |site_key| outcome.results_by_site.fetch(site_key, []) },
        errors: outcome.errors_by_site,
        searchedSites: site_keys,
        searchedLocations: locations,
        countsBySite: outcome.results_by_site.transform_values(&:size)
      }
    end

    private

    def parallel_search
      Research::ParallelSiteSearch.new(
        services: SERVICES, timeout_seconds: SITE_TIMEOUT_SECONDS, log_prefix: "[CommunityResearch]"
      )
    end
  end
end
