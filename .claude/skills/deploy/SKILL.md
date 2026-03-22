---
name: deploy
description: Herokuへのデプロイ。Docker Container Registryを使ったrails-backendのビルド・push・release。
user-invocable: true
---

# Heroku デプロイ手順

**対象**: `rails-backend` → `event_kokuthi_app_backend`
**方式**: Heroku Container Registry（Docker）

---

## 初回セットアップ（初めてのデプロイ時のみ）

```bash
# 1. Heroku CLI ログイン
heroku login
heroku container:login

# 2. アドオン追加
heroku addons:create heroku-postgresql:mini -a <APP_NAME>
heroku addons:create heroku-redis:mini -a <APP_NAME>

# 3. 環境変数設定
heroku config:set RAILS_ENV=production -a <APP_NAME>
heroku config:set SECRET_KEY_BASE=$(cd rails-backend && bundle exec rails secret) -a <APP_NAME>
heroku config:set LME_EMAIL=... -a <APP_NAME>
heroku config:set LME_PASSWORD=... -a <APP_NAME>
heroku config:set LME_BASE_URL=https://step.lme.jp -a <APP_NAME>
heroku config:set LME_BOT_ID=17106 -a <APP_NAME>
heroku config:set API2CAPTCHA_KEY=... -a <APP_NAME>
heroku config:set OPENAI_API_KEY=... -a <APP_NAME>
heroku config:set CONPASS__KOKUCIZE_MAIL=... -a <APP_NAME>
heroku config:set CONPASS_KOKUCIZE_PASSWORD=... -a <APP_NAME>
heroku config:set PEATIX_EMAIL=... -a <APP_NAME>
heroku config:set PEATIX_PASSWORD=... -a <APP_NAME>
```

---

## 通常デプロイ手順

```bash
cd rails-backend

# 1. Dockerイメージをビルドして Heroku Container Registry に push
heroku container:push web -a <APP_NAME>

# 2. リリース（コンテナを有効化）
heroku container:release web -a <APP_NAME>

# 3. DBマイグレーション（スキーマ変更がある場合）
heroku run rails db:migrate -a <APP_NAME>

# 4. ログ確認
heroku logs --tail -a <APP_NAME>
```

---

## デプロイ後の確認

```bash
# アプリの状態確認
heroku ps -a <APP_NAME>

# ログ確認（エラーがないか）
heroku logs --tail -a <APP_NAME>

# APIの疎通確認
curl https://<APP_NAME>.herokuapp.com/api/texts/event

# LMEテスト投稿
# → /lme-test スキルを実行
```

---

## トラブルシューティング

```bash
# コンテナのシェルに入る
heroku run bash -a <APP_NAME>

# 環境変数確認
heroku config -a <APP_NAME>

# Dynoのメモリ使用量確認
heroku ps:scale -a <APP_NAME>

# メモリ不足でクラッシュする場合 → Standard-2X に変更
heroku ps:type standard-2x -a <APP_NAME>
```

---

## Dyno プラン目安

| プラン | RAM | 月額 | Playwright |
|--------|-----|------|-----------|
| Basic | 512MB | $7 | ⚠️ ギリギリ（--disable-dev-shm-usage 必須） |
| Standard-1X | 512MB | $25 | ⚠️ 同上 |
| Standard-2X | 1GB | $50 | ✅ 安定 |

---

## フロントエンドデプロイ（Vercel）

```bash
cd react-frontend
vercel deploy --prod
```

> フロントエンドはVercelで動作するが、Playwright系の投稿機能はバックエンドのみで実行される。
