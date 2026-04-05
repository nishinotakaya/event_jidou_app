---
name: connpass
description: connpass投稿自動化 — CSRF対応・ブラウザ内fetch・画像アップロード・即時公開の全ステップ完了
---

# connpass投稿自動化スキル

## 概要

connpass（connpass.com）へのイベント自動投稿。ログイン後にCSRFトークンを取得し、ブラウザ内fetchでイベント作成・更新。画像アップロードと公開はPlaywrightで操作。

## 投稿フロー

```
1. https://connpass.com/editmanage/ にアクセス（認証チェック）
2. ログイン（未認証時）
   - https://connpass.com/login/ に遷移
   - input[name="username"],input[name="email"] にメールアドレス入力
   - input[name="password"] にパスワード入力
   - form:has(input[name="username"]) button[type="submit"] クリック
   - ログイン後 URL に /login が含まれないことを確認
3. CSRFトークン取得
   - Cookie `connpass-csrftoken` から page.evaluate() で抽出
   - 全APIリクエストのヘッダーに使用
4. イベント作成（POST /api/event/）
   - title, allow_conflict_join: 'true', place: null
   - レスポンスから event ID を取得
5. イベント更新（PUT /api/event/{eventId}）
   - description_input / description: 告知文
   - status: 'draft'（初期状態は下書き）
   - start_datetime / end_datetime: ISO 8601 形式
   - open_start_datetime: 開催7日前
   - open_end_datetime: 開催1日前
   - participation_types[0].max_participants: 定員
6. 画像アップロード（imagePath がある場合のみ）
   - /event/{eventId}/edit/ に遷移
   - .ImageUpload span をクリック → fileChooser で画像設定
   - 保存ボタンクリック
7. 公開（publishSites.connpass === true の場合のみ）
```

## CSRFトークン取得

```javascript
// Cookie から抽出
document.cookie.split(';').find(c => c.trim().startsWith('connpass-csrftoken='))
```

全APIリクエストに以下ヘッダーを付与:
```
x-csrftoken: <token>
x-requested-with: XMLHttpRequest
content-type: application/json
credentials: include
```

## タイトル処理

- 最大80文字
- 先頭の装飾文字を除去: `#【\s「『`
- 末尾の装飾文字を除去: `】』」\s`
- 空の場合フォールバック: "イベント"

## 説明文処理

- 1行目がタイトルと一致する場合は除去
- Zoom URLがある場合: `\n\n■ Zoom URL\n{zoomUrl}` を末尾に追加

## 日時フォーマット

```
start_datetime:      "YYYY-MM-DDTHH:mm:ss"
end_datetime:        "YYYY-MM-DDTHH:mm:ss"
open_start_datetime: "YYYY-MM-DDT00:00:00"（開催7日前）
open_end_datetime:   "YYYY-MM-DDT00:00:00"（開催1日前）
```

## 公開フロー（2段階フォールバック）

### 方法1: UI操作（プライマリ）
```
1. /event/{eventId}/edit/ に遷移
2. 「即時公開」or「公開する」ボタンを探す
3. ボタンの中心座標をクリック
4. .PopupSubmit ボタン（確認モーダル）をクリック
5. networkidle 待機
```

### 方法2: API操作（フォールバック）
```
1. GET /api/event/{eventId} で現在のイベントデータ取得
2. status を 'published' に変更
3. PUT /api/event/{eventId} で更新
```

## 画像アップロードフロー

```
1. /event/{eventId}/edit/ に遷移
2. 4000ms 待機（React レンダリング完了）
3. .ImageUpload span クリック → fileChooser 発火
4. fileChooser.setFiles(imagePath)
5. 3000ms 待機（アップロード完了）
6. button[type="submit"] or button:has-text("保存") クリック
```

## 環境変数

```
CONPASS__KOKUCIZE_MAIL=xxx@example.com
CONPASS_KOKUCIZE_PASSWORD=xxx
```

## 関連ファイル

- `rails-backend/app/services/posting/connpass_service.rb` - 投稿サービス本体
- `rails-backend/app/jobs/post_job.rb` - バックグラウンドジョブ
- `api/connpass.js` - 旧Node.js版（参考用）

## eventFields スキーマ

```javascript
{
  title: "イベントタイトル",       // 省略時は content 1行目から抽出
  place: "オンライン",            // デフォルト: "オンライン"
  capacity: "50",                // デフォルト: 50
  startDate: "2026-04-15",       // YYYY-MM-DD or YYYY/MM/DD
  startTime: "10:00",            // HH:mm（→ HH:mm:ss に変換）
  endDate: "2026-04-15",         // 省略時は startDate と同じ
  endTime: "12:00",              // HH:mm
  zoomUrl: "https://zoom.us/...", // 省略可、説明文に追加
  imagePath: "/path/to/image.png", // 省略可、DALL-E生成画像
  publishSites: { connpass: true } // 公開トリガー
}
```

## テスト接続設定

```ruby
'connpass' => {
  url: 'https://connpass.com/login/',
  email_sel: 'input[name="username"],input[name="email"]',
  pass_sel: 'input[name="password"]',
  submit_sel: 'button[type="submit"]',
  success_check: ->(page) { !page.url.include?('/login') },
}
```

## 注意事項

- CSRFトークンが取得できない場合は例外を投げる（投稿不可）
- connpassのフォームはReact SPA → 直接DOM操作が必要な箇所あり
- 画像アップロードはReactレンダリング待機が必須（4000ms）
- 公開ボタンは座標クリック（CSSセレクタでは不安定）
