---
name: tunagate
description: つなゲート投稿自動化 — Googleログイン → サークル作成 → イベント作成・チケット・日時・公開の全ステップ完了
---

# つなゲート投稿自動化スキル

## 概要

つなゲート（tunagate.com）へのイベント自動投稿。Googleログイン → イベント作成 → チケット設定 → 日時入力 → 公開/下書き保存まで一貫処理。

## 投稿フロー

```
1. https://tunagate.com/users/sign_in にアクセス
   - 「Googleでログイン」をクリック
   - 既にGoogleセッションがあればそのまま認証通過
   - Googleのパラメータ（state, code等）を自動処理

2. https://tunagate.com/menu に遷移
   - 「イベント作成」をクリック
   - モーダルが開く

3. モーダル内で「新規サークルで追加」を選択

4. フォーム入力
   - イベント名: テキストDBの name
   - イベントの説明: テキストDBの content

5. チケット設定
   - 「チケットの追加」をクリック
   - チケット情報を入力

6. イベント日時
   - カレンダーUIで開催日を選択（必須をクリック）
   - 開始時刻と終了時刻を入力

7. 開催場所
   - 会場名（eventFields.place）の値を入力

8. 募集人数
   - 定員（eventFields.capacity）の値を入力

9. 公開/下書き
   - publishSites.つなゲート === true → 「公開」をクリック
   - それ以外 → 「下書き」をクリック
```

## 認証方式

- **Googleログイン**（OAuthリダイレクト）
- つなゲート独自のメール/パスワードは不要
- Google認証済みセッション（Zoom等で使用済み）を活用
- service_connections テーブルの `google` エントリで管理

## サインインURL

```
https://tunagate.com/users/sign_in?ifx=yBrPZyXgNqee6MeA
```

## 実装ファイル

- `rails-backend/app/services/posting/tunagate_service.rb` — メイン実装
- `rails-backend/app/jobs/post_job.rb` — PostJob から呼出

## フォーム要素（調査必要）

| 項目 | セレクタ（要調査） | 値 |
|---|---|---|
| イベント名 | TBD | テキストDB.name |
| イベントの説明 | TBD | テキストDB.content |
| チケット追加 | TBD（ボタン） | クリック |
| 開催日 | TBD（カレンダーUI） | eventFields.startDate |
| 開始時刻 | TBD | eventFields.startTime |
| 終了時刻 | TBD | eventFields.endTime |
| 開催場所 | TBD | eventFields.place |
| 募集人数 | TBD | eventFields.capacity |
| 公開ボタン | TBD | publishSites.つなゲート |
| 下書きボタン | TBD | !publishSites.つなゲート |

## 注意事項

- Googleログインはリダイレクトが複数回発生するため、waitForNavigation/networkidle で確実に待つ
- モーダル内のフォームはSPAの可能性あり → wait_for_selector で要素出現を待つ
- カレンダーUIは日付ピッカーの実装により入力方法が変わる → 実際のDOM構造を要調査
- チケット追加はモーダル内のボタンクリック → 追加フォームが展開される可能性
