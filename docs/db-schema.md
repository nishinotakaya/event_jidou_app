# DB設計書

## 概要

Rails backend（SQLite3）で管理する全テーブルの定義。
フロントエンド（React）は全てAPIを通じてDBにアクセスし、localStorageは使用しない。

---

## テーブル一覧

| テーブル名 | 用途 | レコード数目安 |
|---|---|---|
| `texts` | イベント告知文・テキストの管理 | 数十〜数百 |
| `zoom_settings` | Zoom ミーティング設定の保存 | 数十 |
| `app_settings` | アプリ設定（KVS方式） | 〜20 |
| `users` | Devise認証ユーザー（Googleログイン対応） | 1〜数名 |
| `service_connections` | 外部サービス接続情報（暗号化パスワード） | 〜6 |

---

## texts

イベント告知文・受講生サポートメッセージなどのテキストデータ。

| カラム | 型 | NULL | デフォルト | 説明 |
|---|---|---|---|---|
| id | integer | NO | auto | 主キー |
| name | string | NO | - | テキスト名（イベント名） |
| content | text | YES | - | テキスト本文 |
| text_type | string | NO | - | 種別（`event` / `student`） |
| folder | string | YES | - | フォルダパス（例: `2026/4月`） |
| created_at | datetime | NO | auto | 作成日時 |
| updated_at | datetime | NO | auto | 更新日時 |

**インデックス**: `text_type`

---

## zoom_settings

Zoomミーティングの接続情報。自動作成・手動保存の両方を格納。

| カラム | 型 | NULL | デフォルト | 説明 |
|---|---|---|---|---|
| id | integer | NO | auto | 主キー |
| zoom_url | string | NO | - | Zoom参加URL |
| meeting_id | string | YES | - | ミーティングID（例: `898 7699 8034`） |
| passcode | string | YES | - | パスコード |
| label | string | NO | - | 保存名（ユーザー指定 or 自動生成） |
| title | string | YES | - | Zoomミーティングタイトル（自動作成時のみ設定） |
| created_at | datetime | NO | auto | 作成日時 |
| updated_at | datetime | NO | auto | 更新日時 |

**自動作成 vs 手動の判別**: `title` が NULL でないものは自動作成されたミーティング。

---

## app_settings

アプリ全体の設定をKey-Value Store方式で保存。
旧localStorage の代替として機能し、ブラウザ/ポートに依存しない。

| カラム | 型 | NULL | デフォルト | 説明 |
|---|---|---|---|---|
| id | integer | NO | auto | 主キー |
| key | string | NO | - | 設定キー（一意） |
| value | text | YES | - | 設定値（文字列） |
| created_at | datetime | NO | auto | 作成日時 |
| updated_at | datetime | NO | auto | 更新日時 |

**インデックス**: `key` (UNIQUE)

### 管理するキー一覧

| キー | 値の例 | 説明 |
|---|---|---|
| `event_gen_date` | `2026-04-06` | イベント開催日 |
| `event_gen_time` | `10:00` | イベント開始時刻 |
| `event_gen_end_time` | `12:00` | イベント終了時刻 |
| `openai_api_key` | `sk-...` | OpenAI APIキー（文章生成・校正・日時調整） |
| `dalle_api_key` | `sk-...` | DALL-E 3 APIキー（画像生成用・未設定時はopenai_api_keyを使用） |
| `lme_gen_checked` | `true` / `false` | LME生成チェック状態 |
| `lme_gen_subtype` | `taiken` / `benkyokai` | LMEイベント種別 |
| `lme_send_date` | `2026-04-06` | LME配信日 |
| `lme_send_time` | `10:00` | LME配信時刻 |
| `lme_zoom_url` | `https://us02web.zoom.us/j/...` | 現在のZoom URL |
| `lme_meeting_id` | `898 7699 8034` | 現在のミーティングID |
| `lme_passcode` | `063315` | 現在のパスコード |
| `post_selected_sites` | `["こくチーズ","Peatix"]` | 投稿先サイト選択（JSON配列） |

---

## users

Devise認証ユーザー。Googleログイン（OmniAuth）対応。

| カラム | 型 | NULL | デフォルト | 説明 |
|---|---|---|---|---|
| id | integer | NO | auto | 主キー |
| email | string | NO | - | メールアドレス（UNIQUE） |
| encrypted_password | string | NO | - | Devise暗号化パスワード |
| name | string | YES | - | 表示名 |
| provider | string | YES | - | OmniAuthプロバイダー（`google_oauth2`） |
| uid | string | YES | - | OmniAuth UID |
| avatar_url | string | YES | - | アバター画像URL |
| reset_password_token | string | YES | - | パスワードリセットトークン |
| reset_password_sent_at | datetime | YES | - | パスワードリセット送信日時 |
| remember_created_at | datetime | YES | - | ログイン記憶日時 |
| created_at | datetime | NO | auto | 作成日時 |
| updated_at | datetime | NO | auto | 更新日時 |

**インデックス**: `email` (UNIQUE), `reset_password_token` (UNIQUE)

---

## service_connections

外部サービスの認証情報。パスワードはAES-256-GCMで暗号化して保存。

| カラム | 型 | NULL | デフォルト | 説明 |
|---|---|---|---|---|
| id | integer | NO | auto | 主キー |
| user_id | integer | YES | - | FK → users（シングルユーザー時はNULL可） |
| service_name | string | NO | - | サービス識別名 |
| email | string | YES | - | ログインメールアドレス |
| encrypted_password_field | string | YES | - | 暗号化パスワード（attr_encrypted） |
| encrypted_password_field_iv | string | YES | - | 暗号化IV |
| status | string | YES | `disconnected` | 接続状態 |
| last_connected_at | datetime | YES | - | 最終接続成功日時 |
| error_message | text | YES | - | エラーメッセージ |
| created_at | datetime | NO | auto | 作成日時 |
| updated_at | datetime | NO | auto | 更新日時 |

**インデックス**: `[user_id, service_name]` (UNIQUE)

### service_name 一覧

| 値 | サービス | ENVフォールバック |
|---|---|---|
| `kokuchpro` | こくチーズ | `CONPASS__KOKUCIZE_MAIL` / `CONPASS_KOKUCIZE_PASSWORD` |
| `connpass` | connpass | `CONPASS__KOKUCIZE_MAIL` / `CONPASS_KOKUCIZE_PASSWORD` |
| `peatix` | Peatix | `PEATIX_EMAIL` / `PEATIX_PASSWORD` |
| `techplay` | TechPlay Owner | `TECHPLAY_EMAIL` / `TECHPLAY_PASSWORD` |
| `zoom` | Zoom | `ZOOM_EMAIL` / `ZOOM_PASSWORD` |
| `lme` | LME（エルメ） | `LME_EMAIL` / `LME_PASSWORD` |

### status 一覧

| 値 | 説明 |
|---|---|
| `disconnected` | 未接続（初期状態） |
| `connected` | 接続済み（テスト成功） |
| `testing` | テスト中 |
| `error` | エラー（テスト失敗） |
| `env` | ENV設定のみ（DB未登録） |

---

## API エンドポイント

### app_settings

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/app_settings` | 全設定取得（`?keys=key1,key2` でフィルタ可） |
| PUT | `/api/app_settings` | 設定の一括更新（JSON body でキー:値のペア） |

#### GET /api/app_settings レスポンス例

```json
{
  "event_gen_date": "2026-04-06",
  "event_gen_time": "10:00",
  "event_gen_end_time": "12:00",
  "lme_zoom_url": "https://us02web.zoom.us/j/89876998034?pwd=...",
  "lme_meeting_id": "898 7699 8034",
  "lme_passcode": "063315"
}
```

#### PUT /api/app_settings リクエスト例

```json
{
  "event_gen_date": "2026-04-13",
  "event_gen_time": "10:00"
}
```

### service_connections

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/service_connections` | 全サービス接続状態一覧 |
| POST | `/api/service_connections` | 接続情報の新規登録 |
| PUT | `/api/service_connections/:id` | 接続情報の更新 |
| DELETE | `/api/service_connections/:id` | 接続の削除 |
| POST | `/api/service_connections/:id/test` | 接続テスト実行（バックグラウンド） |
| POST | `/api/service_connections/test_new` | 新規保存+接続テスト |
| POST | `/api/service_connections/migrate_from_env` | ENV → DB一括移行 |

### sessions

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/current_user` | 現在のログインユーザー情報 |
| DELETE | `/api/logout` | ログアウト |
| GET/POST | `/users/auth/google_oauth2` | Google OAuth開始 |
| GET/POST | `/users/auth/google_oauth2/callback` | Google OAuthコールバック |
