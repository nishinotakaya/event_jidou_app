---
name: tunagate
description: つなゲート投稿自動化 — Net::HTTP JSON API方式でPlaywright不要。イベント作成・チケット・日時・公開の全ステップ完了
---

# つなゲート投稿自動化スキル

## 概要

つなゲート（tunagate.com）へのイベント自動投稿。**Net::HTTP JSON API直接呼び出し方式**（Playwright完全排除）。

## アーキテクチャ

- **方式**: Net::HTTP + JSON API（SPA APIを直接呼び出し）
- **認証**: Cookie認証（Rails Devise）— `_c_tunagate_session` + `remember_user_token`
- **CSRFトークン**: HTMLの`<meta name="csrf-token">`から取得、`X-CSRF-Token`ヘッダーで送信
- **Content-Type**: `application/json`
- **サービスファイル**: `app/services/posting/tunagate_service.rb`

## APIエンドポイント

| メソッド | エンドポイント | 用途 |
|---------|-------------|------|
| GET | `/events/new/{circle_id}` | イベントID自動採番 |
| POST | `/api/event_edit/create_content` | 説明文作成 `{event_id, body, content_type: 1}` |
| POST | `/api/event_edit_submit/draft` | 下書き保存 |
| POST | `/api/event_edit_submit/publish` | 公開保存 |

## 投稿フロー

```
1. 認証: session_data Cookie復元 → GET /menu で検証 → 失敗時はDeviseログイン
2. GET /events/new/{circle_id} → リダイレクト先からevent_id取得
3. POST /api/event_edit/create_content で説明文作成
4. POST /api/event_edit_submit/draft or /publish でイベント保存
   body: { event: {id, title, contents, event_date, ...}, events_plans: [{plan, capacity, ...}] }
5. 削除: draft保存APIにdelete_status: 1を渡す
```

## 重要

- `events_plans`は必須（空だと400エラー）
- circle_id: `220600`（AppSettingで変更可能）
- 日時: `YYYY-MM-DD HH:MM:00`

## 本番テスト: ✅ ローカル・Heroku両方成功
