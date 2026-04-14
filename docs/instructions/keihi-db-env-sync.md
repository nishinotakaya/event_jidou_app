# KEIHI_DB_* 環境変数の整理（Production / Staging 二系統化）

`system@10.201.3.63 (jobcanap02)` 上で、Rails アプリ jobcan-obic が参照する経費購買 DB の接続情報を
**Production (`KEIHI_DB_*`)** と **Staging (`STG_KEIHI_DB_*`)** の 2 系統に分離した手順の決定版。

## 関連パス

| 種類 | パス |
|---|---|
| サーバ | `system@10.201.3.63` (hostname: `jobcanap02`) |
| 作業ディレクトリ | `/home/system/jobcan-obic` |
| シェル env 定義ファイル | `/home/system/.env_jobcan`（`.bashrc` の末尾で `source` される）|
| systemd override（sidekiq 用） | `/etc/systemd/system/sidekiq.service.d/override.conf` |
| Rails 接続定義 | `/home/system/jobcan-obic/config/database.yml` |
| 編集コマンド（systemd） | `sudo vi /etc/systemd/system/sidekiq.service.d/override.conf` |
| 編集後の反映 | `sudo systemctl daemon-reload && sudo systemctl restart sidekiq` |

## 確定値

### Production (`KEIHI_DB_*`)

| 変数 | 値 |
|---|---|
| `KEIHI_DB_HOST` | `10.201.3.39` |
| `KEIHI_DB_PORT` | `3306` |
| `KEIHI_DB_USER` | `keihikoubai` |
| `KEIHI_DB_PASS` | `tamahomekk` |
| 対応 DB | `keihikoubai` (本番) |

### Staging (`STG_KEIHI_DB_*`)

| 変数 | 値 |
|---|---|
| `STG_KEIHI_DB_HOST` | `127.0.0.1` |
| `STG_KEIHI_DB_PORT` | `3307` |
| `STG_KEIHI_DB_USER` | `root` |
| `STG_KEIHI_DB_PASS` | `6jRJqtNG` |
| 対応 DB | `keihikoubai4` (staging) |

## ファイル最終形

### `/home/system/.env_jobcan`

```bash
# === Staging (旧 KEIHI_DB_*) ===
export STG_KEIHI_DB_HOST=127.0.0.1
export STG_KEIHI_DB_PORT=3307
export STG_KEIHI_DB_USER=root
export STG_KEIHI_DB_PASS=6jRJqtNG

# === Production (override.conf に合わせる) ===
export KEIHI_DB_HOST=10.201.3.39
export KEIHI_DB_PORT=3306
export KEIHI_DB_USER=keihikoubai
export KEIHI_DB_PASS=tamahomekk
```

### `/etc/systemd/system/sidekiq.service.d/override.conf`（KEIHI 関連抜粋）

```ini
Environment=KEIHI_DB_HOST=10.201.3.39
Environment=KEIHI_DB_PORT=3306
Environment=KEIHI_DB_USER=keihikoubai
Environment=KEIHI_DB_PASS=tamahomekk
Environment=STG_KEIHI_DB_HOST=127.0.0.1
Environment=STG_KEIHI_DB_PORT=3307
Environment=STG_KEIHI_DB_USER=root
Environment=STG_KEIHI_DB_PASS=6jRJqtNG
```

### `config/database.yml`（該当ブロック）

```yaml
keihikoubai_staging:
  adapter: mysql2
  encoding: utf8mb4
  collation: utf8mb4_general_ci
  database: keihikoubai4
  username: <%= ENV.fetch('STG_KEIHI_DB_USER') %>
  password: <%= ENV.fetch('STG_KEIHI_DB_PASS') %>
  host:     <%= ENV.fetch('STG_KEIHI_DB_HOST') %>
  port:     <%= ENV.fetch('STG_KEIHI_DB_PORT') %>
  pool: 5
  timeout: 10000

keihikoubai_production:
  adapter: mysql2
  encoding: utf8mb4
  collation: utf8mb4_general_ci
  database: keihikoubai
  username: <%= ENV.fetch('KEIHI_DB_USER') %>
  password: <%= ENV.fetch('KEIHI_DB_PASS') %>
  host:     <%= ENV.fetch('KEIHI_DB_HOST') %>
  port:     <%= ENV.fetch('KEIHI_DB_PORT') %>
  pool: 5
  timeout: 10000
```

## 適用手順（再現用）

### Step 1. `.env_jobcan` を書き換える

```bash
cp ~/.env_jobcan ~/.env_jobcan.bak.$(date +%Y%m%d_%H%M%S) && cat > ~/.env_jobcan <<'EOF'
# === Staging (旧 KEIHI_DB_*) ===
export STG_KEIHI_DB_HOST=127.0.0.1
export STG_KEIHI_DB_PORT=3307
export STG_KEIHI_DB_USER=root
export STG_KEIHI_DB_PASS=6jRJqtNG

# === Production (override.conf に合わせる) ===
export KEIHI_DB_HOST=10.201.3.39
export KEIHI_DB_PORT=3306
export KEIHI_DB_USER=keihikoubai
export KEIHI_DB_PASS=tamahomekk
EOF
cat ~/.env_jobcan
```

### Step 2. `override.conf` に STG ブロックを追記

```bash
sudo cp /etc/systemd/system/sidekiq.service.d/override.conf /etc/systemd/system/sidekiq.service.d/override.conf.bak.$(date +%Y%m%d_%H%M%S) && sudo sed -i '/^Environment=KEIHI_DB_PASS=/a\
Environment=STG_KEIHI_DB_HOST=127.0.0.1\
Environment=STG_KEIHI_DB_PORT=3307\
Environment=STG_KEIHI_DB_USER=root\
Environment=STG_KEIHI_DB_PASS=6jRJqtNG' /etc/systemd/system/sidekiq.service.d/override.conf && sudo cat /etc/systemd/system/sidekiq.service.d/override.conf
```

### Step 3. systemd 反映 + sidekiq 再起動

```bash
sudo systemctl daemon-reload && sudo systemctl restart sidekiq && sleep 2 && sudo systemctl status sidekiq --no-pager | head -10
```

## echo 確認コマンド集

### 0. 既存セッションで反映確認（最頻出）

`.env_jobcan` を書き換えた直後、**既に開いているシェル**は古い値のままなので
`source` で読み直してから echo する。

```bash
source ~/.env_jobcan && echo $KEIHI_DB_USER $KEIHI_DB_PASS
```

期待出力:

```
keihikoubai tamahomekk
```

STG 側もまとめて見たい場合:

```bash
source ~/.env_jobcan && echo "PROD: $KEIHI_DB_USER / $KEIHI_DB_PASS @ $KEIHI_DB_HOST:$KEIHI_DB_PORT" && echo "STG : $STG_KEIHI_DB_USER / $STG_KEIHI_DB_PASS @ $STG_KEIHI_DB_HOST:$STG_KEIHI_DB_PORT"
```

### 1. シェル環境変数の値を一括確認

```bash
source ~/.env_jobcan && echo "=== PROD ===" && echo "HOST=$KEIHI_DB_HOST" && echo "PORT=$KEIHI_DB_PORT" && echo "USER=$KEIHI_DB_USER" && echo "PASS=$KEIHI_DB_PASS" && echo "=== STG ===" && echo "HOST=$STG_KEIHI_DB_HOST" && echo "PORT=$STG_KEIHI_DB_PORT" && echo "USER=$STG_KEIHI_DB_USER" && echo "PASS=$STG_KEIHI_DB_PASS"
```

期待出力:

```
=== PROD ===
HOST=10.201.3.39
PORT=3306
USER=keihikoubai
PASS=tamahomekk
=== STG ===
HOST=127.0.0.1
PORT=3307
USER=root
PASS=6jRJqtNG
```

### 2. `env` 一括出力（PROD/STG 8 個まとめて）

```bash
env | grep -E '^(STG_)?KEIHI_DB_' | sort
```

### 3. sidekiq プロセスの実際の環境変数を確認

```bash
PID=$(sudo systemctl show sidekiq -p MainPID | cut -d= -f2) && echo "PID=$PID" && sudo cat /proc/$PID/environ | tr '\0' '\n' | grep -E '^(STG_)?KEIHI_DB_' | sort
```

期待出力:

```
KEIHI_DB_HOST=10.201.3.39
KEIHI_DB_PASS=tamahomekk
KEIHI_DB_PORT=3306
KEIHI_DB_USER=keihikoubai
STG_KEIHI_DB_HOST=127.0.0.1
STG_KEIHI_DB_PASS=6jRJqtNG
STG_KEIHI_DB_PORT=3307
STG_KEIHI_DB_USER=root
```

### 4. systemd unit 設定の echo（override.conf 反映確認）

```bash
sudo systemctl cat sidekiq | grep -E '^Environment=(STG_)?KEIHI_DB_'
```

### 5. Rails 経由の DB 接続確認（PROD/STG 両方）

```bash
cd ~/jobcan-obic && source ~/.env_jobcan && cat > /tmp/_keihi_test.rb <<'EOF'
require "active_record"
require "yaml"
require "erb"

[
  "keihikoubai_staging",
  "keihikoubai_production",
].each do |env_name|
  cfg = YAML.safe_load(ERB.new(File.read("config/database.yml")).result, aliases: true)[env_name]
  puts "=== #{env_name} (host=#{cfg["host"]} port=#{cfg["port"]} user=#{cfg["username"]} db=#{cfg["database"]}) ==="
  begin
    ActiveRecord::Base.establish_connection(cfg)
    c = ActiveRecord::Base.connection
    puts "  Connected:  #{c.active?}"
    puts "  VERSION():  #{c.select_value("SELECT VERSION()")}"
    puts "  DATABASE(): #{c.select_value("SELECT DATABASE()")}"
    puts "  @@hostname: #{c.select_value("SELECT @@hostname")}"
    puts "  Tables:     #{c.tables.size}"
    ActiveRecord::Base.remove_connection
  rescue => e
    puts "  NG: #{e.class}: #{e.message.lines.first.strip}"
  end
end
EOF
RAILS_ENV=staging bundle exec rails runner /tmp/_keihi_test.rb; rm -f /tmp/_keihi_test.rb
```

期待出力:

```
=== keihikoubai_staging (host=127.0.0.1 port=3307 user=root db=keihikoubai4) ===
  Connected:  true
  VERSION():  5.7.28-log
  DATABASE(): keihikoubai4
  @@hostname: orderstg01
  Tables:     43
=== keihikoubai_production (host=10.201.3.39 port=3306 user=keihikoubai db=keihikoubai) ===
  Connected:  true
  VERSION():  5.7.28
  DATABASE(): keihikoubai
  @@hostname: orderap01
  Tables:     44
```

## トラブルシュート

| 症状 | 原因 / 対処 |
|---|---|
| `echo $KEIHI_DB_HOST` で古い値 | `.env_jobcan` 書き換え後に新しいシェルを開くか `source ~/.env_jobcan` で再読込 |
| `許可がありません` | `sudo` 必須（特に override.conf 編集時） |
| heredoc が `EOF: コマンドが見つかりません` で失敗 | `EOF` 行の前に空白を入れない。`<<'EOF'` のクォート必須 |
| ペーストで複数行に分解される | バックスラッシュ継続行をやめて 1 行コマンドに統一 |
| sidekiq 再起動後も値が反映されない | `systemctl daemon-reload` を忘れている。実行後に `restart` |

## 補足

- systemd 配下で動く sidekiq は `.bashrc` / `.env_jobcan` を読まず **override.conf の `Environment=` のみ** を参照する。
  そのため両方を同じ値で同期させておく必要がある。
- 手動オペレーション（`bundle exec rails c`、`mysql` クライアント等）はログインシェル経由なので `.env_jobcan` の値が使われる。
- バックアップは `~/.env_jobcan.bak.YYYYMMDD_HHMMSS` および `override.conf.bak.YYYYMMDD_HHMMSS` に自動保存される。
