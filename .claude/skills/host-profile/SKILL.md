---
name: host-profile
description: 主催者プロフィール（テキスト・アイコン・YouTube）と本文への自動埋め込み機能。AI生成・添削あり。投稿時に全サイト共通で content 末尾にプロフィールセクションを冪等で挿入する。
---

# 主催者プロフィール（host-profile）

## 概要

イベント告知の本文末尾に「主催者からひとこと」として、共通プロフィール（自己紹介・アイコン・自己紹介動画）を**全サイト共通で自動付与**する機能。
読者に「このイベントに参加したらこういう未来が見える」と伝える訴求を、毎回手で貼らずに済むようにする。

- プロフィール本文・アイコン・グローバル YouTube URL は **app_settings に保存（全イベント共通）**
- イベントごとに別の紹介動画を出したい場合は、イベント詳細の **「このイベント専用 YouTube URL」** で per-event override
- プロフィール本文は **AI生成 / AI添削** に対応（`/api/ai/profile`）
- アイコンは **256×256 / JPEG q=0.85** にクライアント側で圧縮してアップロード（容量を抑える）

## データ構造

### app_settings（KVS）
| key | 用途 |
|---|---|
| `host_profile_text` | プロフィール本文（200〜300字推奨） |
| `host_profile_icon_url` | アイコン画像 URL（リサイズ済み JPEG） |
| `host_profile_youtube_url` | グローバル既定の自己紹介 YouTube URL |

### items テーブル
| 列 | 用途 |
|---|---|
| `youtube_url` | per-event の YouTube URL。空ならグローバル既定を使用 |

## API

### `POST /api/ai/profile`

```jsonc
{
  "apiKey": "sk-...",
  "mode":   "generate" | "correct",
  "text":   "（correct時の対象テキスト。generate時は空でOK）",
  "hint":   "（任意）タイトルや専門領域など"
}
```

- `mode: 'generate'` — 200〜300字の参加訴求プロフィールを新規生成
- `mode: 'correct'`  — 既存テキストを「来たくなる」訴求に磨き上げ
- レスポンス: `{ "content": "..." }`
- 実装: `rails-backend/app/controllers/api/ai_controller.rb#profile`
- ルート: `rails-backend/config/routes.rb` の `post "ai/profile"`

## 本文への埋め込み（冪等）

PostModal の `handleSaveContent` で content 末尾に以下を挿入。
**マーカー** で囲み、次回保存時はマーカーで囲まれた既存ブロックを取り除いてから新ブロックを付け直す＝何度保存しても重複しない。

```text
<!-- HOST-PROFILE-START -->
---
## 主催者からひとこと
![](icon-url)

{プロフィール本文}

▶ 自己紹介動画: {YouTube URL}
<!-- HOST-PROFILE-END -->
```

採用される YouTube URL の優先順位:
1. `eventFields.youtubeUrl`（per-event）
2. `hostProfile.youtubeUrl`（グローバル既定）
3. どちらも無ければ `▶ 自己紹介動画:` 行は出力しない

プロフィール本文・アイコン・YouTube が **すべて空** なら、ブロック自体を出さず既存マーカーの除去のみ行う。

実装: `react-frontend/src/components/PostModal.jsx` 上部の
`HOST_PROFILE_START` / `HOST_PROFILE_END` / `stripHostProfile` / `buildHostProfileBlock` / `appendHostProfile`。

## アイコンの圧縮

`resizeIconImage(file, maxSize=256, quality=0.85)`（PostModal.jsx）:

1. FileReader で dataURL 読み込み
2. Image オブジェクトに描画
3. 中央クロップで正方形化 → 256×256 に縮小
4. canvas.toBlob で JPEG q=0.85 出力（おおむね 30〜50KB）
5. 既存 `uploadImage(file)` で `/api/images/upload` に POST

## UI（PostModal）

- **モーダル上部にプロフィールカード**（アイコン + 80字プレビュー + ✏️編集 ボタン）
- 編集モーダル（z-index=100）の構成:
  - アイコン: 🖼️選択（`profileIconInputRef`）/ 🗑クリア
  - 本文: textarea + ✨AI生成 / ✅AI添削
  - グローバル YouTube URL: 入力欄
  - 💾保存 → `saveAppSettings({ host_profile_text, host_profile_icon_url, host_profile_youtube_url })`
- イベント詳細セクション内に **per-event YouTube URL** 入力欄（Peatix イベントID の下）

## 関連ファイル

| ファイル | 役割 |
|---|---|
| `rails-backend/db/migrate/20260422000000_add_youtube_url_to_items.rb` | items.youtube_url カラム追加 |
| `rails-backend/app/controllers/api/ai_controller.rb` | `#profile` メソッド |
| `rails-backend/app/controllers/api/texts_controller.rb` | `youtubeUrl` の create/update/serialize |
| `rails-backend/config/routes.rb` | `POST /api/ai/profile` ルート |
| `react-frontend/src/api.js` | `aiProfile()` クライアント関数 |
| `react-frontend/src/components/PostModal.jsx` | プロフィールカード・編集モーダル・content 埋め込み |

## 注意事項

- マーカー（`<!-- HOST-PROFILE-START -->` / `END`）はユーザーが本文中に手で書かないこと。書くと冪等性が壊れる
- 編集モーダルは「保存」を押すまで `app_settings` に書き込まれない（プレビューはローカルState）
- per-event YouTube URL を空にしてグローバル既定に戻したい場合は、明示的に空欄保存
