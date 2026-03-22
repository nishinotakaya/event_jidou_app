# イベント告知自動投稿アプリ — React Frontend

イベント告知文の管理・AI文章生成・複数SNSへの自動投稿を行うWebアプリのフロントエンド。

## 技術スタック

- **React 18**
- **Vite**
- **ActionCable** (WebSocket — 投稿ログのリアルタイム表示)

## バックエンドリポジトリ

https://github.com/nishinotakaya/event_kokuthi_app_backend

---

## 環境構築

### 必要なもの

- Node.js 18+
- npm

### セットアップ

```bash
# 1. 依存関係インストール
npm install

# 2. 開発サーバー起動
npm run dev
# → http://localhost:5173 で起動

# 3. ビルド
npm run build
```

### バックエンドとの接続

`vite.config.js` のプロキシ設定でバックエンド（デフォルト: `http://localhost:3001`）に接続します。
バックエンドを別ポートで起動している場合は `vite.config.js` の `proxy` を変更してください。

---

## 主な機能

- **テキスト管理** — イベント告知文の作成・編集・フォルダ分類
- **投稿** — LME・こくチーズ・Peatix・connpass・TechPlayへ一括投稿
- **リアルタイムログ** — WebSocketで投稿進捗をリアルタイム表示
- **AI生成** — OpenAI APIを使った告知文の自動生成・添削
- **イベントフィールド** — 開催日時・ZoomURL・LME設定などの入力フォーム

---

## Vercelデプロイ

```bash
# vercel.json が含まれているのでそのままデプロイ可能
vercel deploy
```

> **注意**: Vercelではブラウザ自動化（Playwright）は動作しません。AI機能のみ利用可能です。
