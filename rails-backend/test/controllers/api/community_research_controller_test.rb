require "test_helper"
require "minitest/mock"

# AC-05: コミュニティ検索 API。各サイトのサービスは fake に差し替え、HTTP は一切打たない。
class Api::CommunityResearchControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  ENDPOINT = "/api/research/communities".freeze
  EXPECTED_SITE_ORDER = %w[jimoty_member dmm_salon campfire meetup_group rinri yeg].freeze
  RESPONSE_KEYS = %w[results errors searchedSites searchedLocations countsBySite].freeze

  # search に渡された引数も記録する fake
  class FakeCommunityService
    attr_reader :received_arguments

    def initialize(results)
      @results = results
    end

    def search(keyword, locations)
      @received_arguments = [ keyword, locations ]
      @results
    end
  end

  class FakeFailingCommunityService
    def search(_keyword, _locations)
      raise StandardError, "接続できません"
    end
  end

  setup do
    @user = User.create!(email: "community-tester@example.com", password: "password123", role: "viewer")
    login_as(@user, scope: :user)
  end

  teardown do
    Warden.test_reset!
  end

  def community_services
    Api::CommunityResearchController::SERVICES
  end

  # SERVICES の new を fake に差し替えて block を実行する（複数サイトは再帰で stub を入れ子にする）
  def with_fake_services(fakes_by_site_key, &block)
    return yield if fakes_by_site_key.empty?

    (site_key, fake_instance), *remaining_fakes = fakes_by_site_key.to_a
    community_services.fetch(site_key).stub(:new, -> { fake_instance }) do
      with_fake_services(remaining_fakes.to_h, &block)
    end
  end

  def fakes_for_all_sites(&fake_builder)
    community_services.keys.index_with { |site_key| fake_builder.call(site_key) }
  end

  def post_search(parameters)
    post ENDPOINT, params: parameters, as: :json
  end

  test "SERVICES は登録順どおりで、値は Research::Communities 配下のサービス" do
    assert_equal EXPECTED_SITE_ORDER, community_services.keys
    assert(community_services.values.all? { |service_class| service_class.name.start_with?("Research::Communities::") })
  end

  test "未ログインは 401" do
    Warden.test_reset!
    post_search(keyword: "交流会")

    assert_response :unauthorized
  end

  test "keyword が空白だけなら 422" do
    post_search(keyword: "   ")

    assert_response :unprocessable_entity
  end

  test "keyword が無くても 422" do
    post_search({})

    assert_response :unprocessable_entity
  end

  test "未知の site は searchedSites に入らない" do
    fakes = { "campfire" => FakeCommunityService.new([]) }
    with_fake_services(fakes) do
      post_search(keyword: "交流会", sites: %w[campfire unknown])
    end

    assert_response :success
    assert_equal %w[campfire], response.parsed_body["searchedSites"]
  end

  test "未知の site だけを指定したら全サイトが対象になる" do
    fakes = fakes_for_all_sites { FakeCommunityService.new([]) }
    with_fake_services(fakes) do
      post_search(keyword: "交流会", sites: %w[unknown])
    end

    assert_response :success
    assert_equal EXPECTED_SITE_ORDER, response.parsed_body["searchedSites"]
  end

  test "sites 未指定でも全サイトが対象になる" do
    fakes = fakes_for_all_sites { FakeCommunityService.new([]) }
    with_fake_services(fakes) do
      post_search(keyword: "交流会")
    end

    assert_equal EXPECTED_SITE_ORDER, response.parsed_body["searchedSites"]
  end

  test "成功サイトと例外サイトが混在してもサイト単位で分離され、キー集合は 5 個ちょうど" do
    fakes = {
      "campfire" => FakeCommunityService.new([ { name: "A" }, { name: "B" } ]),
      "rinri" => FakeFailingCommunityService.new
    }
    with_fake_services(fakes) do
      post_search(keyword: "交流会", sites: %w[campfire rinri])
    end

    assert_response :success
    body = response.parsed_body
    assert_equal RESPONSE_KEYS.sort, body.keys.sort
    assert_equal({ "rinri" => "接続できません" }, body["errors"])
    assert_equal({ "campfire" => 2 }, body["countsBySite"])
    assert_equal %w[A B], body["results"].map { |community_result| community_result["name"] }
  end

  test "全サイトが例外でも 200 で、results は空、errors に全サイトが入る" do
    fakes = fakes_for_all_sites { FakeFailingCommunityService.new }
    with_fake_services(fakes) do
      post_search(keyword: "交流会")
    end

    assert_response :success
    body = response.parsed_body
    assert_equal [], body["results"]
    assert_equal EXPECTED_SITE_ORDER.sort, body["errors"].keys.sort
    assert_equal({}, body["countsBySite"])
  end

  test "results はサイトの登録順（sites を逆順で渡しても jimoty_member が先）" do
    fakes = {
      "campfire" => FakeCommunityService.new([ { name: "campfire の結果" } ]),
      "jimoty_member" => FakeCommunityService.new([ { name: "jimoty の結果" } ])
    }
    with_fake_services(fakes) do
      post_search(keyword: "交流会", sites: %w[campfire jimoty_member])
    end

    assert_equal [ "jimoty の結果", "campfire の結果" ],
                 response.parsed_body["results"].map { |community_result| community_result["name"] }
  end

  test "サイト内の取得順は保たれ、日付ソートはしない" do
    fakes = { "campfire" => FakeCommunityService.new([ { name: "Z" }, { name: "A" }, { name: "M" } ]) }
    with_fake_services(fakes) do
      post_search(keyword: "交流会", sites: %w[campfire])
    end

    assert_equal %w[Z A M], response.parsed_body["results"].map { |community_result| community_result["name"] }
  end

  test "locations の未知の値は落ち、既知の値だけ searchedLocations に入りサービスへ渡る" do
    fake_service = FakeCommunityService.new([])
    with_fake_services("campfire" => fake_service) do
      post_search(keyword: "交流会", sites: %w[campfire], locations: %w[東京 火星])
    end

    assert_equal %w[東京], response.parsed_body["searchedLocations"]
    assert_equal [ "交流会", %w[東京] ], fake_service.received_arguments
  end

  test "keyword は前後の空白を除いてサービスへ渡る" do
    fake_service = FakeCommunityService.new([])
    with_fake_services("campfire" => fake_service) do
      post_search(keyword: "  交流会  ", sites: %w[campfire])
    end

    assert_equal "交流会", fake_service.received_arguments.first
  end
end
