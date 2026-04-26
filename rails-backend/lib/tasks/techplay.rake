require 'shellwords'

namespace :techplay do
  desc 'TechPlay の指定イベントの本文 (markdown_description) を取得して表示・空チェック。 例: techplay:smoke[994979]'
  task :smoke, [:event_id] => :environment do |_t, args|
    event_id = args[:event_id] || ENV['EVENT_ID']
    abort 'event_id を指定してください: techplay:smoke[994979]' unless event_id

    require 'playwright'
    email    = ENV.fetch('TECHPLAY_EMAIL')
    password = ENV.fetch('TECHPLAY_PASSWORD')

    pw_local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    wrapper  = '/tmp/playwright-runner.sh'
    File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(pw_local)} \"$@\"\n")
    File.chmod(0o755, wrapper)

    detail_md = nil
    title     = nil
    Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
      browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'])
      context = browser.new_context
      page = context.new_page
      page.goto('https://owner.techplay.jp/auth')
      page.wait_for_selector('#email', timeout: 15_000)
      page.fill('#email', email); page.fill('#password', password)
      page.click('input[type="submit"]')
      page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
      page.goto("https://owner.techplay.jp/event/#{event_id}/edit", waitUntil: 'domcontentloaded')
      page.wait_for_timeout(3500)

      result = page.evaluate(<<~JS)
        (() => {
          const wrappers = [...document.querySelectorAll('.toastui-editor-defaultUI')];
          let detail = null, title = null;
          for (const w of wrappers) {
            let cur = w;
            for (let i = 0; i < 25 && cur; i++) {
              const v = cur.__vue__;
              if (v && v.input && 'markdown_description' in v.input) {
                detail = v.input.markdown_description || '';
                title = (v.input.title || '');
                break;
              }
              cur = cur.parentElement;
            }
            if (detail !== null) break;
          }
          // タイトルは別 component から取り直し
          if (!title) {
            document.querySelectorAll('input[name="title"]').forEach(el => { if (el.value) title = el.value; });
          }
          return { title, detail_head: (detail || '').slice(0, 120), detail_bytes: (detail || '').length };
        })()
      JS
      title     = result['title']
      detail_md = (result['detail_head'] || '')
      detail_bytes = result['detail_bytes'].to_i
      puts "=== techplay:smoke[#{event_id}] ==="
      puts "title: #{title.inspect}"
      puts "markdown_description bytes: #{detail_bytes}"
      puts "markdown_description head: #{detail_md.inspect}"
      browser.close

      if detail_bytes.zero?
        abort "❌ 本文が空です (event_id=#{event_id})"
      else
        puts "✅ 本文あり"
      end
    end
  end

  desc 'Heroku 本番にデプロイされている TechPlay 詳細欄を curl で書き換える。 例: techplay:repair_body[994979,event_018]'
  task :repair_body, %i[event_id item_id] => :environment do |_t, args|
    event_id = args[:event_id] || ENV['EVENT_ID']
    item_id  = args[:item_id]  || ENV['ITEM_ID']
    abort '使い方: techplay:repair_body[event_id,item_id]' unless event_id && item_id

    item = Item.find_by(id: item_id) || abort("Item not found: #{item_id}")
    body = item.content.to_s
    abort "Item.content が空: #{item_id}" if body.empty?
    ENV['PROBE_EVENT_ID'] = event_id
    ENV['BODY_FILE']      = nil
    tmp = "/tmp/techplay_repair_#{item_id}.txt"
    File.write(tmp, body)
    ENV['BODY_FILE'] = tmp
    load Rails.root.join('scripts', 'repair_techplay_body.rb').to_s
  end
end
