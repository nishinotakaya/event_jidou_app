# コミュニティ検索サービスのテスト用ヘルパー。HTTP は一切打たず、フィクスチャ HTML を返す。
module ResearchHttpStub
  COMMUNITY_RESULT_KEYS = %i[site siteLabel name url description area fee memberCount imageUrl organizer].freeze

  def research_fixture(fixture_name)
    file_fixture("research/#{fixture_name}.html").read.force_encoding(Encoding::UTF_8)
  end

  # service#http_get を差し替え、要求された URL を記録した配列を返す。
  # page_bodies の n 番目が n 回目のリクエストの応答になる。足りない分は空文字（fetch_pages が打ち切る）。
  # 要素が Exception なら raise する（404 などの再現用）。
  def stub_http_get(service, page_bodies)
    requested_urls = []
    lock = Mutex.new
    service.define_singleton_method(:http_get) do |url, _headers = {}|
      call_index = lock.synchronize do
        requested_urls << url
        requested_urls.size - 1
      end
      body = page_bodies.fetch(call_index, "")
      raise body if body.is_a?(Exception)

      body
    end
    requested_urls
  end

  def assert_community_result_shape(community_result, service_class)
    assert_equal COMMUNITY_RESULT_KEYS.sort, community_result.keys.sort
    assert_equal service_class::SITE_KEY, community_result[:site]
    assert_equal service_class::SITE_LABEL, community_result[:siteLabel]
    assert service_class::SITE_LABEL.present?, "SITE_LABEL が空"
  end
end
