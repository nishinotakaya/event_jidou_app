require "playwright"
require "shellwords"
pw_path = Rails.root.join("node_modules", ".bin", "playwright").to_s
wrapper = "/tmp/pw.sh"
File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(pw_path)} \"$@\"\n")
File.chmod(0o755, wrapper)

Playwright.create(playwright_cli_executable_path: wrapper) do |pw|
  browser = pw.chromium.launch(headless: true, args: %w[--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage --disable-gpu])
  svc = ServiceConnection.find_by(service_name: "tunagate")
  opts = { userAgent: "Mozilla/5.0", locale: "ja-JP", viewport: { width: 1280, height: 800 } }
  opts[:storageState] = JSON.parse(svc.session_data) if svc&.session_data.present?
  ctx = browser.new_context(**opts)
  page = ctx.new_page
  page.goto("https://tunagate.com/events/new/220600", waitUntil: "domcontentloaded", timeout: 30_000)
  sleep 5
  puts "url: #{page.url}"
  fields = page.evaluate('JSON.stringify(Array.from(document.querySelectorAll("input,textarea,select")).filter(function(e){return e.offsetParent!==null}).slice(0,15).map(function(e){return {tag:e.tagName,type:e.type,name:e.name,val:(e.value||"").substring(0,20)}}))')
  puts "fields: #{fields}"
  browser.close
end
