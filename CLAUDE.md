# イベント告知自動投稿アプリ - Claude Code 設定

## プロジェクト概要

イベント告知文のテキスト管理・AI文章生成・20以上のサイトへの自動投稿を一元管理するWebアプリ。

## 技術スタック

- **バックエンド**: Rails 7.2 APIモード（`rails-backend/`）
  - 開発: Docker Compose（port 3001）+ SQLite / 本番: Heroku（Docker Container Registry）+ JawsDB MySQL
  - 非同期: Sidekiq + Redis（投稿ジョブ・スケジュール配信）
  - ブラウザ自動化: Playwright（Node.jsブリッジ経由）※API化済みサイトは Net::HTTP のみ
  - AI: OpenAI API（gpt-4o-mini / DALL-E 3）
- **フロントエンド**: React + Vite（`react-frontend/`、port 5173、`/api` は 3001 へ proxy）
- **旧実装**: `api/`・`public/`・`texts/` は初代 Node/Express 版（参考用。新機能はRailsに実装する）

## よく使うコマンド

```bash
docker compose up -d        # Rails API + MySQL + Redis 起動（port 3001）
npm run rails               # Rails をローカル起動する場合（rbenv 3.1.2）
npm run react               # React 開発サーバー（http://localhost:5173）
```

デプロイは `/deploy` スキル参照（Heroku Container Registry。worker は Dockerfile.worker を明示）。

## ディレクトリ構成

```
rails-backend/
  app/services/posting/   # サイト別投稿サービス（bizee, connpass, doorkeeper, jimoty,
                          #   kokuchpro, lme, luma, onclass, peatix, seminars, techplay,
                          #   tunagate, twitter, instagram ほか20以上）
  app/controllers/api/    # APIエンドポイント（texts, ai, post, service_connections 等）
  app/jobs/               # PostJob ほか Sidekiq ジョブ
react-frontend/src/
  components/             # PostModal（投稿・AI添削の中心）ほか
  api.js                  # APIクライアント
```

## 投稿サイトの詳細

各サイトのログイン方式・API・ハマりどころは **`.claude/skills/<サイト名>/` のスキルに集約**されている（lme, kokuchpro, peatix, connpass, techplay, onclass, zoom など）。サイトの投稿処理を触る前に該当スキルを必ず参照すること。

## ブランチ構成

- デフォルトブランチは `main`
- 作業ブランチは `fix/xxx` / `feat/xxx` を切って `main` へマージする

## 注意事項

- **認証情報**: `.env` で管理（gitignore済み）。UIから登録する分は DB（service_connections / AppSetting）に保存。絶対にコミットしない
- **本番DB**: リセット・破壊的操作は絶対に事前確認（過去に全データ消失事故あり）
- **投稿系操作**: 実行前に `/posting-rules` を必ず参照。チェック対象外サイトには投稿しない
- **Heroku制約**: Peatix は Heroku IP がブロックされるためローカルでセッション取得（`/peatix` スキル参照）。JawsDB は 5MB / max_questions 制限あり
