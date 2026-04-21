# OnclassReviewNotifyJob ドキュメント

## 概要

GitHub レビュー投稿完了後に、オンクラス（`manager.the-online-class.com`）の
コミュニティチャンネルへレビュー完了通知を Playwright で自動投稿する ActiveJob。

- **ファイル**: `rails-backend/app/jobs/onclass_review_notify_job.rb`
- **キュー**: `:default`
- **トリガー**: `Api::GithubReviewsController#post_to_github` 成功時に `perform_later` で enqueue

## 呼び出しフロー

```
受講生のPRをレビュー
  → GithubReviewScanJob / GithubReReviewJob（レビュー本文生成）
  → POST /api/github_reviews/:id/post_to_github
     └ GithubReviewService#post_comment（GitHubへ投稿）
     └ review.update!(status: 'posted')
     └ OnclassReviewNotifyJob.perform_later(review.id)   ← 本ジョブ
```

## 処理ステップ

| # | ステップ              | 内容                                                           |
| - | --------------------- | -------------------------------------------------------------- |
| 1 | `perform`             | `GithubReview` 取得。`status == 'posted'` 以外は何もせず終了   |
| 2 | `detect_channel`      | リポジトリ名から投稿先チャンネルを推定                         |
| 3 | `build_message`       | 通知本文（PRラベル・URL・コメントURL）を組み立て               |
| 4 | Playwright 起動       | `headless: true` で Chromium を起動                            |
| 5 | `ensure_login`        | `/sign_in` にアクセスしログイン。ログイン済みならスキップ      |
| 6 | `navigate_to_community` | `/community` に遷移                                           |
| 7 | `select_channel`      | サイドバーの `.v-list-item` を探してクリック                   |
| 8 | `send_message`        | textarea にメッセージ入力 → 送信アイコンをクリック             |
| 9 | `ensure`              | 例外発生有無に関わらず `browser.close` でリソース解放          |

## チャンネル振り分けルール

`CHANNEL_ROUTES` 配列を先頭から評価し、最初にマッチしたチャンネルを採用する。

| 条件（リポジトリ名を downcase 後）                 | 投稿先チャンネル   |
| -------------------------------------------------- | ------------------ |
| `todo` と `b` を含む                               | `TodoB - 報告`     |
| `todo` と `a` を含む                               | `TodoA - 報告`     |
| `portfolio` または `ポートフォリオ` を含む         | `クローンチーム`   |
| `pdca` を含む                                      | `PDCAアプリ開発`   |
| 上記いずれにもマッチしない                         | `全体チャンネル`   |

> **NOTE**: 歴史的経緯で `include?` ベースのゆるい判定。
> 想定外のリポジトリ名で誤振り分けが発生しうる。厳密化したい場合は
> `CHANNEL_ROUTES` のマッチラムダを正規表現等に置き換える。

## 認証情報の解決順

`ServiceConnection.credentials_for('onclass')` を通じて以下の優先順で解決する:

1. `ServiceConnection`（DB）に `onclass` エントリがあればそれを使用
2. 無ければ `ENV['ONCLASS_EMAIL']` / `ENV['ONCLASS_PASSWORD']`
3. いずれも空なら `FALLBACK_EMAIL` / `FALLBACK_PASSWORD`（コード内定数）

本番運用では `ServiceConnection` に登録して最終フォールバックに依存しない。

## メッセージフォーマット

```
Gitレビュー完了しました！ご確認のほどお願いします。

📝 {repo_full_name} {PR #N または github_type}
🔗 {github_url}
💬 レビューコメント: {github_comment_url}   ← comment_url があるときのみ
```

## エラー処理方針

- 最外の `rescue => e` で例外をログのみに落とし、リトライしない。
  - 通知失敗でユーザー操作をブロックしたくないため意図的に silent。
  - 失敗時は `logger.error` に `[OnClass通知] ❌ …` として出力される。
- ログインに失敗した場合のみ `'オンクラスログイン失敗'` を raise（最終的には上記 rescue に吸収）。

## 既知の制約・留意点

- Playwright 実行可能パスを `'npx playwright'` でハードコードしている。
  他の Job（例: `OnclassSyncJob#find_playwright_path`）のように動的に解決していない。
  本番デプロイ環境で `npx` が利用可能である必要がある。
- セレクタ（`.v-list-item`, `textarea.v-field__input`, `i.mdi-arrow-up-box`）は
  オンクラスのフロント実装に依存。Vuetify 側の変更で壊れる可能性がある。
- 各ステップに固定の `wait_for_timeout` を挟んでいる（定数化済み）。
  ネットワーク遅延が大きい環境では値の調整が必要。

## 環境変数

| 変数名               | 用途                         | 必須 |
| -------------------- | ---------------------------- | ---- |
| `ONCLASS_EMAIL`      | オンクラス ログイン email    | 推奨 |
| `ONCLASS_PASSWORD`   | オンクラス ログイン password | 推奨 |

※ `ServiceConnection` に登録済みであれば環境変数は不要。

## 関連ファイル

- `rails-backend/app/models/github_review.rb` — レビュー情報の永続化
- `rails-backend/app/models/service_connection.rb` — 認証情報の管理
- `rails-backend/app/services/posting/onclass_service.rb` — 同じサイトを
  対象とした上位レベルの投稿サービス（本 Job の姉妹実装）
- `rails-backend/app/controllers/api/github_reviews_controller.rb` — 呼び出し元
