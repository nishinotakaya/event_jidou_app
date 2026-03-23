---
name: service-connections
description: 外部サービス接続管理 — Devise認証 + 各サービスのメールアドレス/パスワードをUIから登録・接続確認・ステータス表示。Googleログイン対応。
---

# 外部サービス接続管理スキル

## 概要

.envにハードコードされた各サービスの認証情報（メール/パスワード）を、WebUI上の「接続管理」画面から登録・管理できるようにする。Devise によるアプリログイン機能 + 各サービスの接続ステータス管理。

## 対象サービス一覧

| サービス | 認証方式 | 現在の.envキー |
|---|---|---|
| こくチーズ / connpass（共通） | メール + パスワード | `CONPASS__KOKUCIZE_MAIL` / `CONPASS_KOKUCIZE_PASSWORD` |
| Peatix | メール + パスワード | `PEATIX_EMAIL` / `PEATIX_PASSWORD` |
| TechPlay Owner | メール + パスワード | `TECHPLAY_EMAIL` / `TECHPLAY_PASSWORD` |
| Zoom | メール + パスワード | `ZOOM_EMAIL` / `ZOOM_PASSWORD` |
| LME（エルメ） | メール + パスワード | `LME_EMAIL` / `LME_PASSWORD` |
| Google | OAuth 2.0（GOOGLE_CLIENT_ID） | 新規追加 |

## アーキテクチャ

### 1. Devise 認証（アプリログイン）

```
gem 'devise'
gem 'omniauth-google-oauth2'  # Googleログイン

User モデル:
  - email: string (Devise標準)
  - encrypted_password: string (Devise標準)
  - provider: string (omniauth用: 'google_oauth2')
  - uid: string (omniauth用)
  - name: string
  - avatar_url: string
```

### 2. サービス接続情報テーブル

```
service_connections テーブル:
  - id: integer
  - user_id: integer (FK → users)
  - service_name: string (例: 'kokuchpro', 'peatix', 'techplay', 'zoom', 'lme')
  - email: string (暗号化)
  - encrypted_password: string (attr_encrypted)
  - status: string ('disconnected' / 'connected' / 'error')
  - last_connected_at: datetime
  - error_message: text
  - created_at / updated_at

インデックス: [user_id, service_name] UNIQUE
```

### 3. フロントエンド（React）

```
接続管理ページ (/settings/connections):

┌─────────────────────────────────────────────────────┐
│ 🔗 サービス接続管理                                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│ ┌─ こくチーズ / connpass ──────────────────────┐     │
│ │ 📧 takaya314boxing@gmail.com                │     │
│ │ 🟢 接続済み (2026-03-23 12:30)              │     │
│ │ [接続テスト] [編集] [切断]                    │     │
│ └──────────────────────────────────────────────┘     │
│                                                     │
│ ┌─ Peatix ────────────────────────────────────┐     │
│ │ 📧 takaya314boxing@gmail.com                │     │
│ │ 🟢 接続済み                                  │     │
│ │ [接続テスト] [編集] [切断]                    │     │
│ └──────────────────────────────────────────────┘     │
│                                                     │
│ ┌─ TechPlay Owner ────────────────────────────┐     │
│ │ 📧 未設定                                    │     │
│ │ ⚪ 未接続                                    │     │
│ │ [接続する]                                    │     │
│ └──────────────────────────────────────────────┘     │
│                                                     │
│ ┌─ Zoom ──────────────────────────────────────┐     │
│ │ ...                                         │     │
│ └──────────────────────────────────────────────┘     │
│                                                     │
│ ┌─ Google ────────────────────────────────────┐     │
│ │ 🔵 Googleでログイン                          │     │
│ │ ⚪ 未接続                                    │     │
│ └──────────────────────────────────────────────┘     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 4. API エンドポイント

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/service_connections` | 全接続情報一覧（パスワードは返さない） |
| POST | `/api/service_connections` | 新規接続登録 |
| PUT | `/api/service_connections/:id` | 接続情報更新 |
| DELETE | `/api/service_connections/:id` | 接続切断（削除） |
| POST | `/api/service_connections/:id/test` | 接続テスト（実際にログイン試行） |
| GET | `/auth/google_oauth2/callback` | Google OAuth コールバック |

### 5. 接続テスト処理

各サービスの接続テストは、既存の Posting サービスの `ensure_login` メソッドを再利用：

```ruby
# 接続テスト例（TechPlay）
page.goto('https://owner.techplay.jp/auth')
page.fill('#email', connection.email)
page.fill('#password', connection.decrypted_password)
page.click("input[type='submit']")
# ログイン成功判定 → status = 'connected'
# ログイン失敗 → status = 'error', error_message = '...'
```

### 6. 既存コードとの統合

PostJob / 各 Posting Service で接続情報を参照するフォールバック:

```ruby
# 優先順位:
# 1. ServiceConnection（DB）から取得
# 2. ENV['TECHPLAY_EMAIL'] 等（.env フォールバック）

def credentials_for(service_name)
  conn = ServiceConnection.find_by(service_name: service_name, status: 'connected')
  if conn
    { email: conn.email, password: conn.decrypted_password }
  else
    { email: ENV["#{service_name.upcase}_EMAIL"], password: ENV["#{service_name.upcase}_PASSWORD"] }
  end
end
```

## 実装ステップ

### Phase 1: DB + API（バックエンド）
1. `gem 'devise'`, `gem 'attr_encrypted'` 追加
2. `User` モデル生成（Devise）
3. `ServiceConnection` モデル生成
4. `Api::ServiceConnectionsController` CRUD + テストアクション
5. 各 Posting Service に `credentials_for` ヘルパー統合
6. マイグレーション実行

### Phase 2: Googleログイン
1. `gem 'omniauth-google-oauth2'` 追加
2. `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` を .env に追加
3. Devise OmniAuth 設定
4. Google OAuth コールバック処理

### Phase 3: フロントエンド（React）
1. `/settings/connections` ページ作成
2. 接続カード UI コンポーネント
3. 接続登録/編集モーダル
4. 接続テスト実行 + リアルタイムステータス更新
5. Googleログインボタン

### Phase 4: 既存コード統合
1. PostJob のクレデンシャル取得をDB優先に変更
2. 各 Posting Service で `ENV` 直参照を `credentials_for` に置換
3. ZoomJob も同様に対応

## 環境変数（新規追加）

```
GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxx
ENCRYPTION_KEY=32バイトのランダム文字列（attr_encrypted用）
```

## セキュリティ

- パスワードは `attr_encrypted` で AES-256-GCM 暗号化して保存
- API レスポンスにパスワードは含めない
- 接続テスト時のみ復号して使用
- ENCRYPTION_KEY は .env で管理、絶対にコミットしない

## ステータス遷移

```
未接続 (disconnected)
  ↓ ユーザーがメール/パスワード入力 → 接続テスト
接続済み (connected)
  ↓ 接続テスト失敗 or パスワード変更
エラー (error)
  ↓ 再接続テスト成功
接続済み (connected)
```
