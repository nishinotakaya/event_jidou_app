---
name: zoom
description: Zoomミーティング作成自動化 + 設定のDB保存・読み込み・削除
---

# Zoom設定管理スキル

## 概要

Zoomミーティングの作成を自動化し、取得した招待リンク・ミーティングID・パスコードをDBに保存。イベント投稿時に自動読み込みする。

---

## Zoomミーティング作成フロー（Playwright自動化）

### 環境変数

```
ZOOM_EMAIL=takaya314boxing@gmail.com
ZOOM_PASSWORD=Takaya314
```

### 自動化ステップ

```
1. https://zoom.us/signin にアクセス
2. メールアドレスを入力 → 「次へ」クリック
3. パスワードを入力 → 「ログイン」クリック
4. サイドバーの「ミーティング」をクリック
5. 「ミーティングをスケジュール」をクリック
6. フォーム入力:
   - トピック: イベントタイトル（告知アプリの name フィールド）
   - 開催日時: 指定された日付・時刻を入力
7. 「保存」をクリック
8. 作成完了画面から以下を取得:
   - 招待リンク（例: https://us02web.zoom.us/j/81047684037?pwd=xxx）
   - ミーティング ID（例: 810 4768 4037）
   - パスコード（例: abc123）
9. 取得した情報を告知アプリに反映:
   - DB保存: POST /api/zoom_settings
   - フロントエンド: eventFields.zoomUrl / zoomId / zoomPasscode にセット
```

### 取得対象データ

| データ | 取得元 | 用途 |
|--------|--------|------|
| 招待リンク | 保存後の「招待リンク」セクション | 各投稿サイトのZoom URL欄 |
| ミーティング ID | 保存後の詳細画面 | LME通知テンプレート |
| パスコード | 保存後の詳細画面 | LME通知テンプレート |

### 告知アプリへの連携

取得した3つの値を以下に反映する:

1. **DB保存** → `POST /api/zoom_settings` でラベル付きで永続化
2. **PostModal** → `eventFields.zoomUrl` / `zoomId` / `zoomPasscode` に自動入力
3. **EditModal** → LME向け Zoom URL / ミーティングID / パスコード欄に自動入力
4. **localStorage** → `lme_zoom_url` / `lme_meeting_id` / `lme_passcode` に同期

### 実装済みの自動化

**バックエンドファイル:**
- `rails-backend/app/services/zoom_service.rb` - Zoom Playwright 自動化サービス
- `rails-backend/app/jobs/zoom_job.rb` - バックグラウンドジョブ（ActionCable でリアルタイムログ）
- `rails-backend/lib/tasks/zoom_login.rake` - 初回ログインセッション保存（`rake zoom:login`）

**APIエンドポイント:**
- `POST /api/zoom/create_meeting` - ミーティング自動作成（title, startDate, startTime, duration）

**Reactフロントエンド:**
- PostModal に「🔄 自動作成」ボタン追加
- ActionCable でリアルタイムログ表示
- 作成完了後に Zoom URL / ID / パスコードを自動入力

### セッション管理

- 初回は `rake zoom:login` で GUI ブラウザを開き、手動ログインしてセッション保存
- セッションは `rails-backend/tmp/zoom_session.json` に保存
- 以降は headless モードでバックグラウンド実行

### Playwright実装の注意点

- Zoom はheadless検出が厳しい → 初回ログインは GUI モード（`rake zoom:login`）で実行が必須
- セッション保存後は headless でも動作する（`storageState` で復元）
- フォームは React SPA → 日付・時刻は JS evaluate で入力（標準 input/select ではない）
- 保存ボタンは `<button>` タグの「保存」（ナビリンクの「スケジュール」`<a>` と区別が必要）
- パスコードはページ上でマスク表示（`********`）→ 招待コピーから取得を試行
- タイトルに開催日を自動付与（例: 「3/31 テスト体験会」）

---

## アーキテクチャ

### データベース

**テーブル: `zoom_settings`**

| カラム | 型 | 説明 |
|--------|------|------|
| id | integer | PK |
| label | string | 設定の識別名（例: 定例ミーティング） |
| zoom_url | string | Zoom ミーティングURL |
| meeting_id | string | ミーティングID |
| passcode | string | パスコード |
| created_at | datetime | 作成日時 |
| updated_at | datetime | 更新日時 |

### Rails API エンドポイント

| メソッド | パス | 説明 |
|----------|------|------|
| GET | `/api/zoom_settings` | 全設定取得（更新日時降順） |
| POST | `/api/zoom_settings` | 新規保存 |
| PUT | `/api/zoom_settings/:id` | 更新 |
| DELETE | `/api/zoom_settings/:id` | 削除 |

**リクエストパラメータ（POST/PUT）:**
```json
{
  "label": "定例ミーティング",
  "zoom_url": "https://us02web.zoom.us/j/84192949741?pwd=...",
  "meeting_id": "841 9294 9741",
  "passcode": "470487"
}
```

**レスポンス（GET）:**
```json
[
  {
    "id": 1,
    "label": "定例ミーティング",
    "zoomUrl": "https://us02web.zoom.us/j/84192949741?pwd=...",
    "meetingId": "841 9294 9741",
    "passcode": "470487",
    "updatedAt": "2026-03-22 15:30"
  }
]
```

### 関連ファイル

**Rails backend:**
- `rails-backend/app/models/zoom_setting.rb` - モデル（label, zoom_url必須）
- `rails-backend/app/controllers/api/zoom_settings_controller.rb` - CRUD コントローラー
- `rails-backend/config/routes.rb` - ルーティング定義
- `rails-backend/db/migrate/XXXXXX_create_zoom_settings.rb` - マイグレーション

**React frontend:**
- `react-frontend/src/api.js` - API関数（fetchZoomSettings, saveZoomSetting, updateZoomSetting, deleteZoomSetting）
- `react-frontend/src/components/PostModal.jsx` - 投稿画面のZoom読み込み/保存UI
- `react-frontend/src/components/EditModal.jsx` - 編集画面のZoom読み込み/保存UI
- `react-frontend/src/index.css` - Zoomドロップダウンのスタイル

### UIフロー

1. **読み込み**: Zoom URLラベル横の「📥 読み込み」ボタン → ドロップダウンで保存済み設定一覧 → クリックでフォームに自動入力
2. **保存**: Zoom URL入力後「💾 保存」ボタン → ラベル名入力 → DBに保存
3. **削除**: ドロップダウン内の「✕」ボタン → 確認ダイアログ → DB削除

### データフロー

```
[DB] zoom_settings
  ↓ GET /api/zoom_settings
[React] zoomList state
  ↓ ユーザーが選択
[React] eventFields.zoomUrl / zoomId / zoomPasscode
  ↓ localStorage にも同期（EditModal と PostModal で共有）
[Rails] POST /api/post → eventFields として各投稿サービスへ
```

## トラブルシューティング

- **読み込みボタンが反応しない**: Railsサーバー（port 3001）が起動しているか確認
- **保存に失敗する**: `label` と `zoom_url` は必須。空の場合バリデーションエラー
- **マイグレーション未実行**: `cd rails-backend && bin/rails db:migrate`
