---
name: peatix
description: Peatix投稿自動化 — イベント作成・配信URL・カテゴリ・画像・チケット設定の全ステップ完了
---

# Peatix投稿自動化スキル

## 概要

Peatix（peatix.com）へのイベント自動投稿。Bearer API でイベント作成後、Playwright で編集ウィザード全ステップを完了させる。

## 投稿フロー

```
1. ログイン（PEATIX_EMAIL / PEATIX_PASSWORD）
2. Bearer トークン取得（localStorage）
3. POST /v4/events でイベント作成（API）
4. 編集画面 /event/{id}/edit/basics に遷移（Playwright）
5. basics ページ:
   - 配信プラットフォームURL: Zoom URL を入力
   - イベントへの参加方法: Zoom URL・ミーティングID・パスコード（数字）を記載
   - 「進む」クリック
6. details ページ:
   - カテゴリ: 「スキルアップ/資格」を選択
   - サブカテゴリ: 生成AI, AIエージェント, リモートワーク, プログラミング, 転職
   - カバー画像: DALL-E 3 生成画像をアップロード（input[type="file"]）
   - イベント詳細: 改行が消えている場合に自動修正
   - 「保存して進む」クリック
7. tickets ページ:
   - 「無料チケット」カードをクリック
   - チケット名: 「無料チケット」
   - 販売締切日: 開催日と同じ（例: 2026/04/20）
   - 販売締切時刻: 開始時刻と同じ（例: 14:00）
   - 「保存して進む」クリック → 完了
```

## 参加方法テンプレート

```
以下のZoom URLからご参加ください。
開始5分前になりましたらご入室いただけます。

■ Zoom参加情報
参加URL: https://us02web.zoom.us/j/xxx
ミーティングID: 874 2020 4723
パスコード: 311071
```

## 環境変数

```
PEATIX_EMAIL=xxx@example.com
PEATIX_PASSWORD=xxx
PEATIX_CREATE_URL=https://peatix.com/group/16510066/event/create
```

## 関連ファイル

- `rails-backend/app/services/posting/peatix_service.rb` - 投稿サービス本体
- `rails-backend/app/jobs/post_job.rb` - バックグラウンドジョブ
- `api/peatix.js` - 旧Node.js版（参考用）

## 技術的な注意点

- **Bearer認証**: ログイン後に `localStorage.peatix_frontend_access_token` から取得
- **API + Playwright混在**: イベント作成はAPI（高速・確実）、ウィザード操作はPlaywright
- **カテゴリ選択**: select要素またはクリック型UI（Peatixの実装に依存）
- **サブカテゴリ**: checkbox またはボタン型（テキストマッチでクリック）
- **カバー画像**: `input[type="file"]` に `setInputFiles()` で設定
- **改行修正**: 詳細文が1行になっている場合、句読点・記号で自動改行
- **チケット**: 無料・50枚・個別締切なし（デフォルト）
