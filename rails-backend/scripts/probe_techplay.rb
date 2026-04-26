require 'playwright'
require 'json'
require 'shellwords'

EMAIL    = ENV.fetch('TECHPLAY_EMAIL')
PASSWORD = ENV.fetch('TECHPLAY_PASSWORD')
EVENT_ID = ENV.fetch('PROBE_EVENT_ID', '994979')

# 本物の本文を壊さないため、解析用にユニークなマーカーを入れる
TEST_BODY = "[probe-#{Time.now.to_i}]\n\n本文セット動作確認用テキスト。後で正規本文に上書きされます。"

playwright_local = '/Users/nishinotakaya/6.イベント 自動告知アプリ/rails-backend/node_modules/.bin/playwright'
wrapper = '/tmp/playwright-runner.sh'
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(playwright_local)} \"$@\"\n")
File.chmod(0o755, wrapper)

records = []
session_state = nil

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'])
  context = browser.new_context(userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36')
  page = context.new_page

  page.on('request',  ->(r) { records << { phase: @phase || 'init', dir: 'req', method: r.method, url: r.url, post_data: r.post_data, headers: r.headers } })
  page.on('response', ->(r) { records << { phase: @phase || 'init', dir: 'res', status: r.status, url: r.url, content_type: r.headers['content-type'] } })

  # ===== 1. ログイン =====
  @phase = 'login'
  puts '[1/4] ログイン中...'
  page.goto('https://owner.techplay.jp/auth', waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_selector('#email', timeout: 15_000)
  page.fill('#email', EMAIL)
  page.fill('#password', PASSWORD)
  page.click('input[type="submit"]')
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
  if page.url.include?('select_menu')
    page.goto('https://owner.techplay.jp/dashboard', waitUntil: 'domcontentloaded') rescue nil
  end
  puts "    -> #{page.url}"

  # ===== 2. 編集ページ =====
  @phase = 'edit_page'
  puts "[2/4] /event/#{EVENT_ID}/edit へ"
  page.goto("https://owner.techplay.jp/event/#{EVENT_ID}/edit", waitUntil: 'domcontentloaded', timeout: 30_000)
  page.wait_for_selector('.toastui-editor-defaultUI', state: 'attached', timeout: 30_000)
  page.wait_for_timeout(5000)

  # ===== 3-pre. 詳細セクションの DOM 構造を吸い出す =====
  dom_dump = page.evaluate(<<~JS)
    (() => {
      const wrappers = [...document.querySelectorAll('.toastui-editor-defaultUI')];
      // 最後の (=詳細欄) について、上方向に section root を探して周辺DOMをダンプ
      const editor = wrappers[wrappers.length - 1];
      let cur = editor;
      let sectionRoot = null;
      for (let i = 0; i < 15 && cur; i++) {
        cur = cur.parentElement;
        if (!cur) break;
        // section / .panel / .row / .eventEdit_row 等
        if (cur.matches && (cur.matches('section') || cur.className.includes('row') || cur.className.includes('panel') || cur.className.includes('eventEdit'))) {
          sectionRoot = cur; break;
        }
      }
      sectionRoot = sectionRoot || editor.parentElement.parentElement.parentElement;

      // section 内のクリック可能要素を収集
      const clickable = [];
      sectionRoot.querySelectorAll('*').forEach(el => {
        const tag = el.tagName.toLowerCase();
        const cls = (el.className || '').toString();
        const aria = el.getAttribute('aria-label') || '';
        const title = el.getAttribute('title') || '';
        const onclick = el.getAttribute('onclick') || '';
        const role = el.getAttribute('role') || '';
        const r = el.getBoundingClientRect();
        const visible = r.width > 0 && r.height > 0;
        const hasVueClick = Object.keys(el).some(k => k.startsWith('__vue') || k.startsWith('__on'));
        const interesting = (
          /edit|pencil|pen|icon-edit/i.test(cls) ||
          /編集|edit/i.test(aria) || /編集|edit/i.test(title) ||
          tag === 'button' || (tag === 'a' && el.getAttribute('href') === '#') ||
          onclick || role === 'button'
        );
        if (interesting && visible) {
          clickable.push({ tag, cls: cls.toString().slice(0,80), aria, title, onclick: onclick.slice(0,40), role, text: (el.innerText || '').trim().slice(0,30), top: Math.round(r.top), left: Math.round(r.left) });
        }
      });

      return {
        section_tag: sectionRoot ? sectionRoot.tagName : null,
        section_class: sectionRoot ? (sectionRoot.className || '').toString().slice(0,120) : null,
        section_html_head: sectionRoot ? sectionRoot.outerHTML.slice(0, 2500) : null,
        clickable_elements: clickable.slice(0, 50),
      };
    })()
  JS
  puts '===== 詳細セクション root ====='
  puts "tag=#{dom_dump['section_tag']} class=\"#{dom_dump['section_class']}\""
  puts '----- 可視クリック要素 -----'
  dom_dump['clickable_elements'].each_with_index { |e, i| puts "  ##{i} <#{e['tag']} class=\"#{e['cls']}\" aria=\"#{e['aria']}\" title=\"#{e['title']}\"> top=#{e['top']} text=\"#{e['text']}\"" }
  puts '----- section_html_head (先頭2.5KB) -----'
  puts dom_dump['section_html_head']
  puts '-' * 80

  # ===== 3. 本文セット (これがセクションを編集モードに切り替える) =====
  @phase = 'set_body'
  puts '[3/4] setMarkdown 実行（編集モードがトリガーされる）'
  set_result = page.evaluate(<<~JS, arg: TEST_BODY)
    (text) => {
      const findEditor = (wrap) => {
        let cur = wrap;
        for (let i = 0; i < 20 && cur; i++) {
          const v = cur.__vue__;
          if (v && v.$refs) {
            for (const k in v.$refs) {
              const r = v.$refs[k];
              if (r && typeof r.invoke === 'function') return r;
            }
          }
          cur = cur.parentElement;
        }
        return null;
      };
      const wrappers = [...document.querySelectorAll('.toastui-editor-defaultUI')];
      const editors = wrappers.map(findEditor).filter(Boolean);
      if (editors.length === 0) return { ok: false, reason: 'no editor' };
      const PRIVACY_MARK = '申し込み時にご提供いただいた情報';
      const candidates = editors.filter(ed => {
        try { return !((ed.invoke('getMarkdown') || '').includes(PRIVACY_MARK)); }
        catch (e) { return true; }
      });
      const target = candidates[candidates.length - 1] || editors[editors.length - 1];
      target.invoke('setMarkdown', text);
      return { ok: true, total: editors.length, candidates: candidates.length, set_value_head: target.invoke('getMarkdown').slice(0, 60) };
    }
  JS
  puts "    -> #{set_result.inspect}"

  # ===== 4. 保存 =====
  page.wait_for_timeout(1500)
  records.clear
  @phase = 'save'
  visible_save_count = page.locator('button:visible:has-text("保存")').count
  puts "[4/4] 可視「保存」ボタン: #{visible_save_count} 個 → クリック"
  page.locator('button:visible:has-text("保存")').first.click
  page.wait_for_load_state('networkidle', timeout: 30_000) rescue nil
  page.wait_for_timeout(4000)

  session_state = context.storage_state
  browser.close
end

# ===== 結果出力 =====
def safe_dump(obj)
  case obj
  when String
    s = obj.dup.force_encoding('UTF-8')
    s.valid_encoding? ? s : "[binary #{obj.bytesize}B base64=#{[obj].pack('m0')[0,200]}]"
  when Hash  then obj.transform_values { |v| safe_dump(v) }
  when Array then obj.map { |v| safe_dump(v) }
  else obj
  end
end
File.write('/tmp/techplay_probe_records.json', JSON.pretty_generate(safe_dump(records)))
File.write('/tmp/techplay_probe_session.json', JSON.pretty_generate(safe_dump(session_state))) if session_state

puts "\n===== 保存フェーズで飛んだ HTTP =====\n"
records.each do |r|
  next if r[:dir] == 'res'
  next if r[:method] == 'GET'
  next unless r[:url] =~ %r{/api/|/event/|graphql}i
  puts "#{r[:method]} #{r[:url]}"
  if r[:post_data]
    body = r[:post_data].to_s
    puts "  payload(#{body.bytesize}B): #{body[0, 800]}"
  end
  puts ''
end

puts "\n===== 保存フェーズの HTTP レスポンス =====\n"
records.each do |r|
  next unless r[:dir] == 'res'
  next unless r[:url] =~ %r{/api/|/event/|graphql}i
  next if r[:status].to_i < 200
  puts "#{r[:status]} #{r[:url]} (#{r[:content_type]})"
end

puts "\n全リクエスト/レスポンス: /tmp/techplay_probe_records.json (#{records.length} 件)"
