require "test_helper"
require "minitest/mock"

# AC-02: ParallelSiteSearch 切り出し後も ResearchController#search のレスポンス構造が変わらないこと。
# 各サイトのサービスは fake に差し替え、HTTP は一切打たない。
class Api::ResearchControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  RESPONSE_KEYS = %w[
    results errors searchedSites searchedLocations searchedDateFrom searchedDateTo countsBySite browserFallbacks
  ].freeze

  # 全サイトの開始日が「今日以降」になるよう、遠い未来の日付を使う
  LATE_EVENT = { title: "遅いイベント", startsAt: "2099-12-31T10:00:00+09:00" }.freeze
  EARLY_EVENT = { title: "早いイベント", startsAt: "2099-01-01T10:00:00+09:00" }.freeze
  UNDATED_EVENT = { title: "日付なしイベント", startsAt: nil }.freeze

  class FakeSearchService
    def initialize(results)
      @results = results
    end

    def search(_keyword, _locations)
      @results
    end
  end

  class FakeFailingService
    def search(_keyword, _locations)
      raise StandardError, "接続できません"
    end
  end

  setup do
    @user = User.create!(email: "research-tester@example.com", password: "password123", role: "viewer")
    login_as(@user, scope: :user)
  end

  teardown do
    Warden.test_reset!
  end

  # SERVICES の new を fake に差し替えて block を実行する（複数サイトは再帰で stub を入れ子にする）
  def with_fake_services(fakes_by_site_key, &block)
    return yield if fakes_by_site_key.empty?

    (site_key, fake_instance), *remaining_fakes = fakes_by_site_key.to_a
    service_class = Api::ResearchController::SERVICES.fetch(site_key)
    service_class.stub(:new, ->(_date_range) { fake_instance }) do
      with_fake_services(remaining_fakes.to_h, &block)
    end
  end

  test "未ログインは 401" do
    Warden.test_reset!
    post "/api/research/search", params: { keyword: "交流会" }, as: :json

    assert_response :unauthorized
  end

  test "keyword が空なら 422" do
    post "/api/research/search", params: { keyword: "  " }, as: :json

    assert_response :unprocessable_entity
    assert_equal "キーワードを入力してください", response.parsed_body["error"]
  end

  test "成功サイトと例外サイトが混在してもサイト単位で分離され、キー構造が保たれる" do
    with_fake_services(
      "kokuchpro" => FakeSearchService.new([ LATE_EVENT, UNDATED_EVENT, EARLY_EVENT ]),
      "connpass" => FakeFailingService.new
    ) do
      post "/api/research/search", params: { keyword: "交流会", sites: %w[kokuchpro connpass] }, as: :json
    end

    assert_response :success
    body = response.parsed_body
    assert_equal RESPONSE_KEYS.sort, body.keys.sort
    assert_equal({ "connpass" => "接続できません" }, body["errors"])
    assert_equal({ "kokuchpro" => 3 }, body["countsBySite"])
    assert_equal %w[kokuchpro connpass], body["searchedSites"]
    assert_equal [], body["searchedLocations"]
    assert_equal({}, body["browserFallbacks"])
  end

  test "results は startsAt 昇順で、未設定は末尾" do
    with_fake_services(
      "kokuchpro" => FakeSearchService.new([ LATE_EVENT, UNDATED_EVENT ]),
      "connpass" => FakeSearchService.new([ EARLY_EVENT ])
    ) do
      post "/api/research/search", params: { keyword: "交流会", sites: %w[kokuchpro connpass] }, as: :json
    end

    titles = response.parsed_body["results"].map { |result| result["title"] }
    assert_equal %w[早いイベント 遅いイベント 日付なしイベント], titles
  end

  test "失敗したサイトのうち search_api_urls を持つ Peatix だけ browserFallbacks に入る" do
    with_fake_services(
      "peatix" => FakeFailingService.new,
      "connpass" => FakeFailingService.new
    ) do
      post "/api/research/search", params: { keyword: "交流会", sites: %w[peatix connpass] }, as: :json
    end

    body = response.parsed_body
    assert_equal %w[connpass peatix], body["errors"].keys.sort
    assert_equal %w[peatix], body["browserFallbacks"].keys
    assert_equal %w[headers urls], body["browserFallbacks"]["peatix"].keys.sort
  end
end
