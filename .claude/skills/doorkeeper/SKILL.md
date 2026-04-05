---
name: doorkeeper
description: Doorkeeper投稿自動化 — ログイン・イベント作成・日時入力・公開の全ステップ完了
---

# Doorkeeper投稿自動化スキル

## 概要

Doorkeeper（manage.doorkeeper.jp）へのイベント自動投稿。Playwright でログイン → イベント作成 → 保存 → 公開まで一貫処理。

## 投稿フロー

```
1. ログイン（https://manage.doorkeeper.jp/user/sign_in）
   - input[name="user[email]"] にメールアドレス入力
   - input[name="user[password]"] にパスワード入力
   - input[type="submit"],button[type="submit"] クリック
   - ログイン後 URL に /dashboard or /groups が含まれることを確認

2. イベント作成ページへ移動
   - https://manage.doorkeeper.jp/groups/{GROUP_NAME}/events/new

3. フォーム入力
   - タイトル: input[name="event[title]"],input#event_title（最大100文字）
   - 説明: textarea[name="event[description]"],textarea#event_description
     - 非表示の場合 CodeMirror / contenteditable にフォールバック
   - 開始日時: input[name='event[starts_at]']
   - 終了日時: input[name='event[ends_at]']
   - 会場名: input[name="event[venue_name]"],input#event_venue_name
   - 定員: input[name*="ticket_limit"],input[name*="capacity"]

4. 保存: 最後の button[type="submit"] or input[type="submit"] をクリック

5. 公開（publishSites.Doorkeeper === true の場合のみ）
   - 「公開する」「公開」「Publish」ボタンを探してクリック
   - 確認ダイアログ:「はい」「OK」「公開する」「Publish」「確認」をクリック
```

## 日時入力のポイント

Vue/React フレームワークを回避するため、native HTML property setter を使用:

```javascript
const setter = Object.getOwnPropertyDescriptor(
  window.HTMLInputElement.prototype, 'value'
).set;
setter.call(el, value);
el.dispatchEvent(new Event('input', { bubbles: true }));
el.dispatchEvent(new Event('change', { bubbles: true }));
```

## 説明欄のフォールバック

textarea が非表示の場合の代替入力:

```javascript
// 1. 標準 textarea
const ta = document.querySelector('textarea[name="event[description]"]');
if (ta) { ta.value = text; ta.dispatchEvent(new Event('input', { bubbles: true })); return; }
// 2. CodeMirror エディタ
const cm = document.querySelector('.CodeMirror');
if (cm && cm.CodeMirror) { cm.CodeMirror.setValue(text); return; }
```

## 環境変数

| 変数名 | 用途 | 必須 |
|---|---|---|
| `DOORKEEPER_EMAIL` | ログインメールアドレス | DB優先、ENVフォールバック |
| `DOORKEEPER_PASSWORD` | ログインパスワード | DB優先、ENVフォールバック |
| `DOORKEEPER_GROUP_NAME` | グループスラッグ（URL用） | 必須（未設定で例外） |

## eventFields マッピング

| フィールド | ソース | デフォルト |
|---|---|---|
| タイトル | `ef['title']` or content 1行目 | "イベント" |
| 説明 | `content` パラメータ | — |
| 開始日 | `ef['startDate']` | 30日後 |
| 開始時刻 | `ef['startTime']` | "10:00" |
| 終了日 | `ef['endDate']` | startDate と同じ |
| 終了時刻 | `ef['endTime']` | "10:00" |
| 会場名 | `ef['place']` | "オンライン" |
| 定員 | `ef['capacity']` | "50" |

## 公開フロー

```
1. ボタンテキスト検索: ['公開する', '公開', 'Publish']
2. 最初に見つかったボタンをクリック
3. 2000ms 待機
4. 確認ダイアログ検索: ['はい', 'OK', '公開する', 'Publish', '確認']
5. 確認ボタンをクリック
6. networkidle 待機（30s）
```

公開ボタンが見つからない場合は下書き保存のみ（警告ログ出力）。

## 関連ファイル

- `rails-backend/app/services/posting/doorkeeper_service.rb` - 投稿サービス本体
- `rails-backend/app/jobs/post_job.rb` - PostJob から `Posting::DoorkeeperService` を呼出（line 97）
- `rails-backend/app/jobs/test_connection_job.rb` - 接続テスト設定（lines 50-56）

## テスト接続設定

```ruby
'doorkeeper' => {
  url: 'https://manage.doorkeeper.jp/user/sign_in',
  email_sel: 'input[name="user[email]"]',
  pass_sel: 'input[name="user[password]"]',
  submit_sel: 'input[type="submit"],button[type="submit"]',
  success_check: ->(page) { !page.url.include?('/sign_in') },
}
```

## エラーメッセージ

| エラー | 原因 |
|---|---|
| `[Doorkeeper] メールアドレスが未設定です` | credentials なし |
| `[Doorkeeper] ログイン失敗` | URL が /sign_in のまま |
| `[Doorkeeper] DOORKEEPER_GROUP_NAME が未設定です` | ENV 未設定 |
| `[Doorkeeper] タイトル入力欄が見つかりません` | DOM 変更 |
| `[Doorkeeper] 保存ボタンが見つかりません` | DOM 変更 |

## ログインの技術的注意点（重要）

`manage.doorkeeper.jp` のログインフォームを通常submitすると `www.doorkeeper.jp` にリダイレクトされ、manage側のセッションcookieが設定されない問題がある。

**解決策**: `fetch('/user/sign_in', { redirect: 'manual' })` で直接POSTすることでmanage側にセッションcookieが設定される。

## テスト実績（2026-03-27）

- **ログイン**: ✅ fetch POST方式で成功
- **グループ作成**: ✅ `ad050a2ba2efb388a4a9e42ce0`
- **イベント作成**: ✅ ID:196072 で作成完了（タイトル・日時・オンラインURL・説明文・チケット(無料)・定員）
- **実際のセレクタ**: `event[title_ja]`, `#event_starts_at_date`, 時刻はselect(4i/5i), hidden(1i/2i/3i)要同期, `#event_online_event_url`(required), `#event_ticket_types_attributes_0_description_ja`(required)

## セットアップ前提条件

1. **メール確認**: Doorkeeperアカウントのメール確認が完了していること
2. **コミュニティ作成**: `https://manage.doorkeeper.jp/groups/new` からコミュニティを手動作成
3. **環境変数設定**: コミュニティURLのスラッグを `.env` に設定
   ```
   DOORKEEPER_GROUP_NAME=your-group-slug
   ```

## 注意事項

- headless: false が必須（headed モードで動作）
- セッション: `tmp/doorkeeper_session.json` にキャッシュ可能
- 保存ボタンは最後の submit 要素をクリック（ページ内に複数存在するため）
- 日時入力は native setter で値をセットし、input/change イベントを dispatch
- manage側ログインは fetch POST + redirect: 'manual' で行う必要がある
