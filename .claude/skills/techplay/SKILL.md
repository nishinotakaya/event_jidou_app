---
name: techplay
description: TechPlay Owner投稿自動化 — イベント作成・日時・参加枠・定員・公開の全ステップ完了
---

# TechPlay Owner 投稿自動化スキル

## 概要

TechPlay Owner（owner.techplay.jp）へのイベント自動投稿。Playwright でログイン → イベント作成 → 保存 → 公開まで一貫処理。

## 投稿フロー

```
1. ログイン（https://owner.techplay.jp/auth）
   - TECHPLAY_EMAIL / TECHPLAY_PASSWORD
   - input#email / input#password → input[type="submit"]
   - ログイン後 /auth/select_menu に遷移する場合あり → /dashboard へ

2. イベント一覧ページへ移動（/event）
   - 「新規作成」リンクをクリック → /event/create

3. フォーム入力
   - タイトル: input#title
   - 開催日時: input#v-datetimepicker-start（Vue datetimepicker, format: YYYY/MM/DD HH:mm）
   - 終了日時: input#v-datetimepicker-end
   - エリア: input[name="area_types[]"]（チェックボックス: オンライン / 会場）
   - 参加枠名: input[name="attendTypes[0][name]"]
   - 定員数: input[name="attendTypes[0][capacity]"]
   - 申込形式 / 参加費: デフォルト値を使用

4. 保存: button[type="submit"]:has-text("保存")
   → /event/{id}/edit に遷移

5. 公開（publishSites.TechPlay が true の場合のみ）
   - 「公開する」ボタンをクリック
   - 確認ダイアログがあれば承認
```

## 環境変数

| 変数名 | 用途 |
|---|---|
| `TECHPLAY_EMAIL` | ログインメールアドレス |
| `TECHPLAY_PASSWORD` | ログインパスワード |

## 実装ファイル

- `rails-backend/app/services/posting/techplay_service.rb` — メイン実装
- `rails-backend/app/jobs/post_job.rb` — PostJob から `Posting::TechplayService` を呼出

## Vue Datetimepicker 入力のポイント

- `input#v-datetimepicker-start/end` は Vue コンポーネント管理
- 通常の `fill()` では Vue の reactivity がトリガーされない
- `nativeInputValueSetter` で value を直接セットし、`input` / `change` / `blur` イベントを dispatch する
- カレンダーポップアップが開く場合は `Escape` で閉じる

## テスト方法

```bash
cd rails-backend
bin/rails runner 'RUBY_SCRIPT'
```

PostModal から TechPlay を選択して投稿テスト可能。
公開トグルをONにすれば自動公開も実行される。
