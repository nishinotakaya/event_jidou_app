---
name: luma
description: Luma投稿自動化 — REST API方式（api2.luma.com）でPlaywright完全不要。Googleログイン→auth-session-key→API直接投稿
---

# Luma投稿自動化スキル

## 概要

Luma（lu.ma / luma.com）へのイベント自動投稿。**REST API直接呼び出し方式**（Playwright完全不要）。

## アーキテクチャ

- **方式**: Net::HTTP REST API（`api2.luma.com`）
- **認証**: `luma.auth-session-key` Cookie（Googleログインで取得）
- **Content-Type**: `application/json`
- **サービスファイル**: `app/services/posting/luma_service.rb`

## 認証フロー

1. ユーザーがアプリUI経由でLumaにGoogleログイン
2. ブラウザから`luma.auth-session-key` Cookieを取得
3. ServiceConnectionの`session_data`にJSON保存
4. APIリクエスト時にCookieとして送信

## APIエンドポイント

| メソッド | URL | 用途 |
|---------|-----|------|
| GET | `/calendar/admin/list` | 認証確認 + カレンダーID取得 |
| POST | `/event/create` | イベント作成 |
| POST | `/event/update` | イベント更新（説明文等） |
| POST | `/event/admin/delete` | イベント削除 |

## イベント作成リクエスト

```json
POST https://api2.luma.com/event/create
Cookie: luma.auth-session-key=usr-xxx.yyy
{
  "name": "イベント名",
  "start_at": "2026-04-20T11:30:00.000Z",
  "duration_interval": "PT1H",
  "timezone": "Asia/Tokyo",
  "calendar_api_id": "cal-pAQcVXC34JzVcRE",
  "visibility": "public",
  "location_type": "offline",
  "ticket_types": [{"type": "free", ...}],
  "zoom_meeting_url": "https://zoom.us/j/xxx"
}
```

## 重要

- `calendar_api_id`: `cal-pAQcVXC34JzVcRE`（Personal calendar）
- 日時はUTC（JSTから-9時間）
- `duration_interval`: ISO 8601 duration（`PT1H` = 1時間）
- auth-session-keyの有効期限は不明（定期的にGoogleログインで更新必要）

## 本番テスト: ✅ ローカル・Heroku両方成功（1.7秒で完了、メモリ問題なし）
