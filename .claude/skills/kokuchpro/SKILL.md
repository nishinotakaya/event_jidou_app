---
name: kokuchpro
description: こくチーズ（kokuchpro）投稿自動化 — イベント作成・画像アップロード・チケット追加・メール設定
---

# こくチーズ投稿自動化スキル

## 概要

こくチーズ（kokuchpro.com）へのイベント自動投稿。Playwright によるブラウザ自動化。

## 投稿フロー

```
1. https://www.kokuchpro.com/regist/ にアクセス
2. ログイン（CONPASS__KOKUCIZE_MAIL / CONPASS_KOKUCIZE_PASSWORD）
3. Step1: イベント種別選択（参加型・無料）
4. Step2: フォーム入力
   - タイトル、説明（TinyMCE）、ジャンル
   - 開催日時、終了日時、受付期間（開催7日前〜1日前で自動計算）
   - 定員、会場名、Zoom URL、連絡先TEL・メール
5. 画像アップロード（DALL-E 3 生成画像 → input[type="file"]）
6. 送信ボタンクリック → イベント作成完了
7. チケット追加（自動）
   - チケット名: 「オンラインチケット」
   - 販売枚数: 定員と同じ（デフォルト50）
   - 締切日時: 開催日時と同じ
   - 「追加する」クリック
8. メール設定（自動）
   - メール設定ページ（/edit/mail/e-xxx/d-xxx/）に遷移
   - 申込完了メール: イベント詳細 + Zoom参加情報（URL/ID/パスコード）
   - キャンセルメール: キャンセル確認 + イベント情報
   - 「更新する」クリック
```

## チケット追加フロー（詳細）

イベント作成完了後、管理画面のURLから自動遷移：

```
1. 投稿完了URL（例: https://www.kokuchpro.com/admin/e-xxx/d-xxx/）
2. 「チケット」リンクをクリック or /ticket/ に直接アクセス
3. 「イベントチケットの追加」ボタンをクリック
4. フォーム入力:
   - チケット名: 「オンラインチケット」
   - 販売枚数: eventFields.capacity（デフォルト50）
   - 締切日: 開催日と同じ（startDate）
   - 締切時刻: 開始時刻と同じ（startTime）
5. 「追加する」ボタンをクリック
```

## メール設定フロー（詳細）

チケット追加完了後、メール設定ページに自動遷移：

```
1. メール設定URL（例: https://www.kokuchpro.com/edit/mail/e-xxx/d-xxx/）に遷移
2. 申込完了メール本文を自動入力:
   - イベント名、開催日時（日本語曜日付き）、会場
   - Zoom参加情報（URL、ミーティングID、パスコード）
   - 開始5分前入室の案内
3. キャンセルメール本文を自動入力:
   - キャンセル対象イベント情報
   - お礼メッセージ
4. 「更新する」ボタンをクリック
```

### 申込完了メールテンプレート例

```
この度はお申込みいただきありがとうございます。

■ イベント詳細
━━━━━━━━━━━━━━━━
イベント名: {title}
開催日時: 2026年3月29日(日) 10:00〜12:00
会場: オンライン
━━━━━━━━━━━━━━━━

■ Zoom参加情報
━━━━━━━━━━━━━━━━
参加URL: https://us02web.zoom.us/j/xxx
ミーティングID: 874 2020 4723
パスコード: abc123
━━━━━━━━━━━━━━━━

※ 開始5分前になりましたらURLよりご入室ください。

ご不明な点がございましたら、お気軽にお問い合わせください。
当日お会いできることを楽しみにしております。
```

### パスコード表示の注意

- Zoom自動作成時、パスコードはページ上でマスク表示（`********`）
- メール本文ではZoom URLの `pwd=` パラメータから実パスコードを自動抽出して表示
- ユーザーが手入力したパスコードがある場合はそちらを優先

## 公開/非公開

- PostModal の各サイト横に「公開/非公開」トグルボタン（デフォルト: 非公開）
- 公開にチェックした場合:
  - 管理画面（/admin/e-xxx/d-xxx/）に遷移
  - 「公開する」ボタンをクリック
- eventFields.publishSites でサイトごとに制御

## 環境変数

```
CONPASS__KOKUCIZE_MAIL=xxx@example.com
CONPASS_KOKUCIZE_PASSWORD=xxx
```

## 関連ファイル

- `rails-backend/app/services/posting/kokuchpro_service.rb` - 投稿サービス本体
- `rails-backend/app/jobs/post_job.rb` - バックグラウンドジョブ（DALL-E画像生成含む）
- `api/kokuchpro.js` - 旧Node.js版（参考用）

## フォーム構造の注意点

- 説明欄は TinyMCE エディタ → `tinymce.editors[].setContent()` で操作
- 日付は jQuery UI Datepicker → `$(el).datepicker('setDate', ...)` で操作
- 時刻は `<select>` → `setSelectOpt()` で操作
- 画像は `input[type="file"]` → `setInputFiles()` で操作
- 日次投稿制限あり（1日3件まで）→ エラー検知して raise

## 画像について

- **生成**: DALL-E 3 API（1024x1024 PNG）
- **スタイル**: 可愛い系（パステル水彩）/ かっこいい系（幾何学モダン）
- **保存先**: `rails-backend/tmp/event_image_{timestamp}_{job_id}.png`
- **アップロード**: `input[type="file"]` に `setInputFiles()` で設定
- **クリーンアップ**: 投稿完了後に自動削除（post_job.rb ensure ブロック）
