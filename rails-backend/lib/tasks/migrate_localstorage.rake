namespace :settings do
  desc "Import settings from localStorage JSON (paste from browser console)"
  task :import_from_localstorage, [:json_string] => :environment do |_t, args|
    json = args[:json_string]
    unless json.present?
      puts <<~USAGE
        使い方:
        1. ブラウザの開発者コンソールで以下を実行してJSONをコピー:

           copy(JSON.stringify({
             event_gen_date:    localStorage.getItem('event_gen_date'),
             event_gen_time:    localStorage.getItem('event_gen_time'),
             event_gen_end_time:localStorage.getItem('event_gen_end_time'),
             openai_api_key:    localStorage.getItem('openai_api_key'),
             lme_gen_checked:   localStorage.getItem('lme_gen_checked'),
             lme_gen_subtype:   localStorage.getItem('lme_gen_subtype'),
             lme_send_date:     localStorage.getItem('lme_send_date'),
             lme_send_time:     localStorage.getItem('lme_send_time'),
             lme_zoom_url:      localStorage.getItem('lme_zoom_url'),
             lme_meeting_id:    localStorage.getItem('lme_meeting_id'),
             lme_passcode:      localStorage.getItem('lme_passcode'),
             post_selected_sites: localStorage.getItem('post_selected_sites'),
           }))

        2. rakeタスクを実行:
           bin/rails "settings:import_from_localstorage[{ここにJSON}]"
      USAGE
      next
    end

    data = JSON.parse(json)
    imported = 0
    data.each do |key, value|
      next if value.nil? || value.empty?
      AppSetting.set(key, value)
      puts "  ✅ #{key} = #{value.truncate(50)}"
      imported += 1
    end
    puts "\n#{imported} 件インポート完了"
  end

  desc "List all app settings"
  task list: :environment do
    settings = AppSetting.order(:key)
    if settings.empty?
      puts "設定なし"
    else
      settings.each do |s|
        val = s.key.include?('api_key') ? "#{s.value[0..7]}..." : s.value.truncate(60)
        puts "  #{s.key}: #{val}"
      end
    end
  end
end
