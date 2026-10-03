require "test_helper"
require "minitest/mock"

# AC-02: サイト並列検索の「成功 / 例外 / 遅延」の分離を fake サービスで検証する（HTTP は打たない）
class Research::ParallelSiteSearchTest < ActiveSupport::TestCase
  TIMEOUT_SECONDS = 0.3

  class SucceedingService
    def self.results
      [ { title: "成功イベント", startsAt: "2030-01-01T10:00:00+09:00" } ]
    end
  end

  class RaisingService; end

  class SlowService; end

  SERVICES = {
    "succeeding" => SucceedingService,
    "raising" => RaisingService,
    "slow" => SlowService
  }.freeze

  def run_search(site_keys)
    searcher = Research::ParallelSiteSearch.new(services: SERVICES, timeout_seconds: TIMEOUT_SECONDS)
    searcher.run(site_keys) do |service_class|
      case service_class.name
      when SucceedingService.name then SucceedingService.results
      when RaisingService.name then raise StandardError, "サイトが壊れています"
      when SlowService.name
        sleep TIMEOUT_SECONDS * 5
        []
      end
    end
  end

  test "成功したサイトの結果が results_by_site に入る" do
    outcome = run_search(%w[succeeding])

    assert_equal({ "succeeding" => SucceedingService.results }, outcome.results_by_site)
    assert_empty outcome.errors_by_site
  end

  test "例外を投げたサイトは errors_by_site にメッセージが入り、他サイトの結果は残る" do
    outcome = run_search(%w[succeeding raising])

    assert_equal "サイトが壊れています", outcome.errors_by_site["raising"]
    assert_equal SucceedingService.results, outcome.results_by_site["succeeding"]
    assert_not outcome.results_by_site.key?("raising")
  end

  test "タイムアウトしたサイトは「タイムアウトしました」になり、他サイトの結果は残る" do
    outcome = run_search(%w[succeeding slow])

    assert_equal "タイムアウトしました", outcome.errors_by_site["slow"]
    assert_equal SucceedingService.results, outcome.results_by_site["succeeding"]
    assert_not outcome.results_by_site.key?("slow")
  end

  test "タイムアウトを待つ時間は全サイト並列で 1 回分だけ（直列に待たない）" do
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run_search(%w[slow slow raising])
    elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert_operator elapsed_seconds, :<, TIMEOUT_SECONDS * 4
  end

  test "指定した site_keys だけが対象になる" do
    outcome = run_search(%w[succeeding])

    assert_equal %w[succeeding], outcome.results_by_site.keys
    assert_not outcome.errors_by_site.key?("raising")
    assert_not outcome.errors_by_site.key?("slow")
  end

  test "ブロックにはサイトのサービスクラスが渡される" do
    received_classes = Queue.new
    searcher = Research::ParallelSiteSearch.new(services: SERVICES, timeout_seconds: TIMEOUT_SECONDS)
    searcher.run(%w[succeeding]) do |service_class|
      received_classes << service_class
      []
    end

    assert_equal SucceedingService, received_classes.pop
  end
end
