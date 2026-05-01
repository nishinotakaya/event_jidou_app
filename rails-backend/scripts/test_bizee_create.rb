# BIZee の新規イベント作成を実機で確認するスクリプト。
#
# 前提:
#   - ServiceConnection.credentials_for('bizee') に email/password が保存されていること
#     なければ ENV['BIZEE_EMAIL'] / ENV['BIZEE_PASSWORD'] でフォールバック
#
# 実行:
#   bundle exec rails runner rails-backend/scripts/test_bizee_create.rb
#
# 動作:
#   - Net::HTTP で /seminar/b-login → /seminar/b-entry-2 → admin-ajax.php
#   - レスポンス JSON から post_id / permalink を抽出して表示
#
# 注意:
#   - publishSites['BIZee'] = false（下書きの WordPress 状態相当）。実装は post_type=post 固定。
#   - テストイベントは BIZee マイページから手動で削除すること。

require 'date'

# ENV フォールバック（ServiceConnection が空の場合）
if ServiceConnection.respond_to?(:credentials_for) && ServiceConnection.credentials_for('bizee')[:email].blank?
  if ENV['BIZEE_EMAIL'].present? && ENV['BIZEE_PASSWORD'].present?
    ServiceConnection.create_or_find_by!(service_name: 'bizee').update!(
      email: ENV['BIZEE_EMAIL'],
      password: ENV['BIZEE_PASSWORD'],
    ) rescue nil
  end
end

content = <<~MD
  [BIZee 投稿テスト #{Time.now.to_i}]

  これは BizeeService の動作確認用の投稿テストです。
  内容を確認したら BIZee のマイページから削除してください。

  - 動作確認1: ログインで wordpress_logged_in_* Cookie が立つこと
  - 動作確認2: /seminar/b-entry-2 から frontend-form-1_nonce が取れること
  - 動作確認3: admin-ajax.php に multipart POST してレスポンス JSON が返ること
MD

ef = {
  'title'        => "【テスト】BIZee 自動投稿チェック #{Date.today}",
  'startDate'    => (Date.today + 30).strftime('%Y-%m-%d'),
  'startTime'    => '20:30',
  'endTime'      => '21:30',
  'place'        => 'オンライン',
  'capacity'     => '20',
  'zoomUrl'      => 'https://us02web.zoom.us/j/example',
  'organizer'    => '個人事業主・自営業者',
  'publishSites' => { 'BIZee' => false },
}

result = Posting::BizeeService.new.call(nil, content, ef) { |msg| puts msg }
puts "[テスト] 結果: #{result.inspect}"
