# 全サイト投稿・申込者検知テスト結果 (2026-04-01)

## 投稿テスト結果（全12サイト / ジモティ除外）

| サイト | 結果 | URL |
|--------|------|-----|
| こくチーズ | 成功 | kokuchpro.com/admin/e-222.../d-3759086 |
| connpass | 成功 | connpass.com/event/389494 |
| Peatix | 成功 | peatix.com/event/4951873 |
| TechPlay | 成功 | owner.techplay.jp/event/994215 |
| つなゲート | 成功 | URL未取得（後述） |
| Doorkeeper | 成功 | doorkeeper.jp/.../events/196189 |
| ストアカ | 成功 | URL未取得（後述） |
| EventRegist | 成功 | URL未取得（後述） |
| Luma | 成功 | luma.com/event/manage/evt-BX2... |
| セミナーBiZ | 成功 | seminar-biz.com/seminar/102984/events/102711 |
| LME（体験会） | 成功 | step.lme.jp (直接実行で確認) |
| Gmail | 未テスト | Googleトークン期限切れ - 再ログイン必要 |

## 申込者検知テスト結果

| サイト | 検知結果 | 備考 |
|--------|----------|------|
| connpass | 0人 (正常) | Playwright経由で管理画面から取得 |
| Peatix | 0人 (正常) | 同上 |
| こくチーズ | 0人 (正常) | 同上 |
| Doorkeeper | 0人 (正常) | 同上 |
| TechPlay | 0人 (正常) | 同上 |
| Luma | 0人 (正常) | 同上 |
| セミナーBiZ | 0人 (正常) | 同上 |

## URL未取得サイトの原因

- **つなゲート**: 投稿後のpage.urlがサークルページ（/circle/XXXXX）のままで、イベントIDを含むURLがログにも出力されない
- **ストアカ**: 投稿完了後のpage.urlが管理ダッシュボードに遷移し、個別イベントURLが取得できない
- **EventRegist**: 投稿完了後のURLパターンがEVENT_URL_PATTERNSのregexにマッチしない

## 実装変更の概要

### 1. Zoom URL告知除去
- `connpass_service.rb`: 告知本文からZoom情報を削除
- `peatix_service.rb`: 告知本文からZoom情報を削除（配信URL欄・参加方法欄は維持）
- `PostModal.jsx`: 投稿コンテンツへの自動挿入を削除
- 各サイトの専用URL入力欄（place_url, online_event_url等）とメール送信テンプレートは維持

### 2. Gmail告知機能（新規）
- `google-apis-gmail_v1` gem追加
- OAuth scope に `gmail.send` 追加
- `Posting::GmailService` 作成（Zoom情報付きメール送信）
- PostJob、ServiceConnection、フロントエンドに統合

### 3. 申込者検知の改善
- connpass: 廃止APIからHTMLスクレイピングに変更
- Doorkeeper/TechPlay/Luma: 管理URLから公開URLへの変換を追加
- Playwright経由の管理画面チェックを新規追加（非公開イベントにも対応）

### 4. LMEルーティング修正
- PostJobにLMEのcase文が欠落していたのを修正

### 5. リモートイベント削除・中止機能（新規）

#### 実装内容
- `BaseService` に `delete_remote` / `cancel_remote` インターフェース追加
- 全10サイトに `perform_delete` / `perform_cancel` メソッド実装
- `RemoteActionJob` 作成（Playwright並列実行、ActionCable対応）
- API: `DELETE /api/post/:item_id/remote` / `POST /api/post/:item_id/cancel`
- フロントエンド: 削除確認モーダル（「ポータルサイトも削除」/「ローカルのみ削除」選択）
- ItemCardに「中止」ボタン追加（投稿履歴がある場合のみ表示）

#### 削除テスト結果

| サイト | 削除方式 | 結果 |
|--------|----------|------|
| connpass | API DELETE | 成功 |
| Doorkeeper | ブラウザ操作 | 成功 |
| こくチーズ | ブラウザ操作（ログイン後） | 成功 |
| Peatix | API PATCH (draft化) | 成功 |
| TechPlay | 限定公開化 | セッションタイムアウト（要再接続） |
| Luma | 「その他」タブ→Delete | ボタン未検出（要セッション確認） |
| セミナーBiZ | 管理画面操作 | タイムアウト（要再接続） |

#### 注意事項
- TechPlay/Luma/セミナーBiZはブラウザセッションの再保存後に再テスト推奨
- event_urlが未取得のサイト（つなゲート/ストアカ/EventRegist）はURL取得ロジック改善済み（次回投稿から取得可能）
- LMEはブロードキャスト削除の仕組みが異なるためリモート削除対象外

### 6. 参加者情報取得機能（新規）

#### 実装内容
- `ParticipantChecker` サービス作成（Playwrightで各サイトの管理画面から参加者の名前・メールアドレスを取得）
- API: `POST /api/posting_histories/check_participants?item_id=xxx`
- フロントエンド: ItemCardに「👥 参加者確認」ボタン → 参加者一覧テーブル表示

#### 対応サイト
| サイト | 参加者ページURL | 抽出方法 |
|--------|---------------|---------|
| connpass | /event/{id}/participation/ | テーブル・ユーザーリンクスクレイピング |
| Peatix | /event/{id}/orders | オーダーテーブルスクレイピング |
| こくチーズ | 管理画面 | テーブルスクレイピング |
| Doorkeeper | /events/{id}/attendees | テーブルスクレイピング |
| TechPlay | /event/{id}/attendee | テーブルスクレイピング |
| Luma | /event/manage/{evt}/guests | カード・テーブルスクレイピング |
| つなゲート | イベント管理ページ | 汎用テーブルスクレイピング |
| ストアカ | 管理ページ | 汎用テーブルスクレイピング |
| EventRegist | 管理ページ | 汎用テーブルスクレイピング |
| セミナーBiZ | 管理ページ | 汎用テーブルスクレイピング |

#### テスト結果（event_016: 参加者0のテストイベント）
- Doorkeeper: 0人 (正常)
- こくチーズ: 0人 (正常)
- Luma: 0人 (正常)
- ストアカ: 0人 (正常)
- TechPlay: 0人 (正常)
- ※参加者0のため空リストが正しく返ることを確認。参加者がいる場合はテーブル/リストから名前・メールを抽出する設計。
