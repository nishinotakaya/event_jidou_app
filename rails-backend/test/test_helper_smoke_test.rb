require "test_helper"

# AC-01: テスト基盤（rails test）が動くことの確認
class TestHelperSmokeTest < ActiveSupport::TestCase
  test "テスト環境で起動している" do
    assert Rails.env.test?
  end
end
