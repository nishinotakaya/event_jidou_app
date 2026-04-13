---
name: doorkeeper
description: Doorkeeper投稿自動化 — Net::HTTP API方式でPlaywright不要。ログイン・イベント作成・公開の全ステップ完了
---

# Doorkeeper投稿自動化スキル

## 概要

Doorkeeper（manage.doorkeeper.jp）へのイベント自動投稿。**Net::HTTP直接呼び出し方式**（Playwright不要）でログイン → イベント作成 → 保存 → 公開まで一貫処理。

## アーキテクチャ

- **方式**: Net::HTTP（Playwright完全排除）
- **認証**: Cookie認証（Rails Devise）
- **CSRFトークン**: HTMLページの`<meta name="csrf-token">`から取得
- **Content-Type**: `application/x-www-form-urlencoded`（multipart/form-data不要）
- **サービスファイル**: `app/services/posting/doorkeeper_service.rb`

## 投稿フロー（API方式）

```
1. ログイン
   - GET /user/sign_in → CSRFトークン + Cookie取得
   - POST /user/sign_in (form-urlencoded)
     - authenticity_token, user[email], user[password], user[remember_me]=1
   - 302リダイレクト → Cookie保持（remember_user_token, usdksc）

2. イベント作成
   - GET /groups/{group_name}/events/new → CSRFトークン取得
   - POST /groups/{group_name}/events (form-urlencoded)
     - authenticity_token
     - event[title_ja] = タイトル
     - event[starts_at_date] = YYYY/MM/DD
     - event[starts_at_time(1i-5i)] = 年,月,日,時,分（個別）
     - event[ends_at_*] = 同上
     - event[attendance_type] = online
     - event[online_event_url] = Zoom URL
     - event[ticket_types_attributes][0][admission_type] = free
     - event[ticket_types_attributes][0][description_ja] = 参加チケット
     - event[ticket_types_attributes][0][ticket_limit] = 50
     - event[description_ja] = 説明文
     - commit = 作成する
   - 302リダイレクト → /groups/{group}/events/{event_id}

3. 公開（publishSites.Doorkeeper === true の場合）
   - POST /groups/{group}/events/{id}/publish (authenticity_token付き)

4. 削除
   - POST event_path (_method=delete, authenticity_token付き)
```

## 環境変数

- `DOORKEEPER_EMAIL` / `DOORKEEPER_PASSWORD`（ServiceConnectionから取得）
- グループ名: AppSetting `doorkeeper_group_name` or コードのデフォルト値

## 日時フォーマット

- `event[starts_at_date]`: `YYYY/MM/DD`（スラッシュ区切り）
- `event[starts_at_time(1i)]`: 年（例: 2026）
- `event[starts_at_time(2i)]`: 月（0パディングなし、例: 4）
- `event[starts_at_time(3i)]`: 日（0パディングなし）
- `event[starts_at_time(4i)]`: 時（0パディングなし）
- `event[starts_at_time(5i)]`: 分（2桁、例: 00）

## 本番テスト結果

- **ローカル**: ✅ ログイン成功、イベント作成成功、削除成功
- **Heroku本番**: ✅ ログイン成功、イベント作成成功、削除成功
- **メモリ**: Playwright不要のためメモリ問題なし
