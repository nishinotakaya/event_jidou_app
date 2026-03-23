require 'sqlite3'
require 'json'
require 'fileutils'

class ChromeCookieExtractor
  CHROME_COOKIE_DB = File.expand_path('~/Library/Application Support/Google/Chrome/Default/Cookies')

  def self.extract_for_playwright(domain, output_path)
    raise "Chrome Cookie DB not found" unless File.exist?(CHROME_COOKIE_DB)

    # Chromeがロック中なのでコピーして読む
    tmp = "/tmp/chrome_cookies_#{SecureRandom.hex(4)}.db"
    FileUtils.cp(CHROME_COOKIE_DB, tmp)

    db = SQLite3::Database.new(tmp)
    rows = db.execute(
      "SELECT name, value, host_key, path, expires_utc, is_secure, is_httponly FROM cookies WHERE host_key LIKE ?",
      ["%#{domain}%"]
    )
    db.close
    File.delete(tmp) rescue nil

    cookies = rows.map do |name, value, host, path, expires, secure, httponly|
      {
        name: name,
        value: value,
        domain: host,
        path: path.presence || '/',
        expires: expires > 0 ? (expires / 1_000_000 - 11_644_473_600).to_f : -1,
        httpOnly: httponly == 1,
        secure: secure == 1,
        sameSite: 'Lax',
      }
    end

    # Playwright storageState形式で保存
    storage_state = {
      cookies: cookies,
      origins: [],
    }

    File.write(output_path, JSON.pretty_generate(storage_state))
    cookies.length
  end
end
