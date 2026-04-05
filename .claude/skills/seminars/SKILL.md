---
name: seminars
description: セミナーズ投稿自動化 — ログイン・イベント作成・日時・会場・定員・チケット・公開の全ステップ完了
---

# セミナーズ投稿自動化スキル

## 概要

セミナーズ（seminars.jp）へのイベント自動投稿。Playwright でログイン → イベント作成 → フォーム入力 → 保存 → 公開まで一貫処理。

## セットアップ前提条件（重要）

seminars.jp は**主催者として別途申請・審査が必要**なプラットフォーム。
- 通常のユーザー登録だけでは `/user/host/` 配下のページにアクセスできない
- 「このページへのアクセス権がありません」とリダイレクトされる
- ブラウザで手動で主催者申請を行い、審査通過後にイベント作成が可能になる

## テスト実績（2026-03-27）

- **ログイン**: ✅ 成功（`/users/sign_in` → `#user_email` / `#user_password`）
- **プロフィール更新**: ✅ 成功（生年月日・電話番号・氏名・かな）
- **イベント作成**: ⚠️ 主催者権限不足で実際のイベントは作成不可
- **ログインURL**: `https://seminars.jp/users/sign_in`（`/login` は404）
- **作成URL**: `https://seminars.jp/user/host/seminar/seminars/new`（主催者権限必要）

## 投稿フロー

```
1. ログイン（https://seminars.jp/login）
   - メール入力: input[name="email"], input[type="email"], #email
   - パスワード入力: input[name="password"], input[type="password"], #password
   - 送信: button[type="submit"], input[type="submit"]
   - ログイン確認: URL に /login が含まれないこと

2. イベント作成ページへ移動
   - https://seminars.jp/seminars/new

3. フォーム入力
   - タイトル（最大100文字）
   - 説明文（リッチエディタ対応）
   - 開始日時・終了日時
   - 会場（オンライン選択対応）
   - 定員
   - 参加費（無料を選択）

4. 保存ボタンクリック

5. 公開（publishSites.セミナーズ === true の場合のみ）
```

## フォームセレクタ一覧

### タイトル
```
input[name*="title"]
input[name*="name"]
input#title
input#seminar_title
input[type="text"]（フォールバック）
```

### 説明文
```
textarea[name*="description"]
textarea[name*="content"]
textarea[name*="body"]
textarea#description
```

リッチエディタのフォールバック:
- `[contenteditable="true"]` → innerHTML に `<br>` 付きで挿入
- `.ql-editor`（Quill） → innerHTML に挿入
- `.tox-edit-area__iframe`（TinyMCE） → iframe 内に挿入

### 開始日時
```
# 日付
input[name*="start_date"], input[name*="startDate"], input[name*="date_start"]
# 時刻
input[name*="start_time"], input[name*="startTime"], input[name*="time_start"]
# 結合型フォールバック
input[name*="start"], input[type="datetime-local"]
```

### 終了日時
```
# 日付
input[name*="end_date"], input[name*="endDate"], input[name*="date_end"]
# 時刻
input[name*="end_time"], input[name*="endTime"], input[name*="time_end"]
```

### 会場（オンライン）
```
input[value*="online"]
label:has-text('オンライン') input
input[name*="online"]
```
place に「オンライン」が含まれる場合、チェックボックスを自動選択。

### 定員
```
input[name*="capacity"]
input[name*="limit"]
input#capacity
```

### 参加費（無料）
```
input[value="0"]
input[value="free"]
label:has-text('無料') input
```

### 保存ボタン
```
button[type="submit"]:has-text('保存')
button[type="submit"]:has-text('登録')
input[type="submit"]
button[type="submit"]（汎用フォールバック）
```

## 入力ヘルパー: set_input_value

```ruby
def set_input_value(page, locator, value)
  locator.click
  sleep 0.2
  locator.fill(value)
  page.keyboard.press('Escape') rescue nil
  sleep 0.2
end
```

日付/時刻入力のカレンダーポップアップを Escape で閉じる。

## 日時入力の処理

```ruby
def fill_date_input(page, type, date, time)
  # 1. 個別の日付・時刻入力を試行
  # 2. 時刻入力が見つからない場合、datetime-local を試行
  # 3. フォーマット: "YYYY-MM-DDTHH:MM"
end
```

- 時刻は0パディング: "9:00" → "09:00"
- デフォルト開始日: 30日後
- デフォルト開始時刻: "10:00"

## 公開フロー

```
1. ボタンテキスト検索（優先順）:
   - button:has-text('公開する'), button:has-text('公開')
   - button:has-text('掲載する'), button:has-text('掲載')
   - a:has-text('公開する'), a:has-text('公開')
   - a:has-text('掲載する'), a:has-text('掲載')
   - input[value='公開する'], input[value='掲載する']
2. ボタンクリック
3. 2000ms 待機
4. 確認ダイアログ: 「はい」「OK」「公開する」「掲載する」「確認」
5. 確認ボタンクリック
6. networkidle 待機（30s）
```

## 環境変数

| 変数名 | 用途 | 備考 |
|---|---|---|
| `SEMINARS_EMAIL` | ログインメールアドレス | DB優先、ENVフォールバック |
| `SEMINARS_PASSWORD` | ログインパスワード | DB優先、ENVフォールバック |

現時点では .env に未設定。ServiceConnection の UI から登録が必要。

## eventFields マッピング

| フィールド | ソース | デフォルト |
|---|---|---|
| タイトル | `ef['title']` or content 1行目 | "イベント"（最大100文字） |
| 説明 | `content` パラメータ | — |
| 開始日 | `ef['startDate']` | 30日後 |
| 開始時刻 | `ef['startTime']` | "10:00" |
| 終了日 | `ef['endDate']` | startDate と同じ |
| 終了時刻 | `ef['endTime']` | — |
| 会場 | `ef['place']` | "オンライン" |
| 定員 | `ef['capacity']` | "50" |

## 関連ファイル

- `rails-backend/app/services/posting/seminars_service.rb` - 投稿サービス本体
- `rails-backend/app/jobs/post_job.rb` - PostJob から呼出（line 98: `'セミナーズ'`）
- `rails-backend/app/jobs/test_connection_job.rb` - 接続テスト設定（lines 57-63）

## テスト接続設定

```ruby
'seminars' => {
  url: 'https://seminars.jp/login',
  email_sel: 'input[name="email"],input[type="email"],#email',
  pass_sel: 'input[name="password"],input[type="password"],#password',
  submit_sel: 'button[type="submit"],input[type="submit"]',
  success_check: ->(page) { !page.url.include?('/login') },
}
```

## エラーメッセージ

| エラー | 原因 |
|---|---|
| `[セミナーズ] メールアドレスが未設定です` | credentials なし |
| `[セミナーズ] メール入力欄が見つかりません` | セレクタ不一致 |
| `[セミナーズ] パスワード入力欄が見つかりません` | セレクタ不一致 |
| `[セミナーズ] ログイン失敗` | URL が /login のまま |
| `[セミナーズ] タイトル入力欄が見つかりません` | DOM 変更 |
| `[セミナーズ] 保存ボタンが見つかりません` | DOM 変更 |

## 注意事項

- headless: false 必須（headed モード）
- リッチエディタの種類によって入力方法が異なる（textarea / contenteditable / Quill / TinyMCE）
- 改行は `<br>` タグに変換してリッチエディタに挿入
- セレクタは複数パターンを優先順で試行（サイトUI変更への耐性）
