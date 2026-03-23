---
name: service-connections
description: 外部サービス接続管理 — Devise認証 + 各サービスのメールアドレス/パスワードをUIから登録・接続確認・ステータス表示。Googleログイン対応。
---

# 外部サービス接続管理 + 認証ルール

## 認証ルール（絶対遵守）

### before_action :authenticate_user!

- `ApplicationController` に `before_action :authenticate_user!` を設定
- **全APIエンドポイントはログイン必須**（401 Unauthorized を返す）
- 例外: `Api::SessionsController`（login / current_user / csrf_token）は `skip_before_action`

### データのユーザースコープ

- **items（テキスト）**: `current_user.items` でスコープ。他ユーザーのデータは見えない
- **folders**: `current_user.folders` でスコープ。他ユーザーのフォルダは見えない
- **service_connections**: `user_id` で紐付け
- **新規作成時**: 必ず `current_user.items.new(...)` / `user_id: current_user.id` でユーザーを紐付ける

### コントローラーの書き方ルール

```ruby
# OK: ユーザースコープで取得
items = current_user.items.where(item_type: params[:type])

# NG: 全ユーザーのデータが見える
items = Item.where(item_type: params[:type])

# OK: ユーザースコープでfind
item = current_user.items.find_by(id: params[:id])

# NG: 他ユーザーのデータにアクセスできる
item = Item.find(params[:id])
```

### Userモデルのアソシエーション

```ruby
class User < ApplicationRecord
  has_many :items, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :service_connections, dependent: :destroy
end
```

## 対象サービス一覧

| サービス | service_name | ENVフォールバック |
|---|---|---|
| こくチーズ / connpass | kokuchpro / connpass | `CONPASS__KOKUCIZE_MAIL` / `CONPASS_KOKUCIZE_PASSWORD` |
| Peatix | peatix | `PEATIX_EMAIL` / `PEATIX_PASSWORD` |
| TechPlay Owner | techplay | `TECHPLAY_EMAIL` / `TECHPLAY_PASSWORD` |
| Zoom | zoom | `ZOOM_EMAIL` / `ZOOM_PASSWORD` |
| LME | lme | `LME_EMAIL` / `LME_PASSWORD` |

## 接続ステータス

- 保存時に自動的に `connected` に設定
- 投稿成功/失敗で PostJob が自動更新（success → connected, error → error）
- 接続テストボタンは即座に `connected` を返す（Playwrightテスト廃止）

## Googleログイン

- OmniAuth Google OAuth2（GETリクエスト許可）
- 既存メールアドレスのユーザーにはprovider/uid/avatarを紐付け
- 新規メールは自動ユーザー作成
- ログイン成功後 `/?login=success` にリダイレクト

## ログイン画面

- 未認証時は必ずログイン画面を表示（スキップ不可）
- メール/パスワード or Googleログイン
- seedユーザー: `takaya314boxing@gmail.com` / `Takaya314!`
