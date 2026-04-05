---
name: onclass
description: オンクラス（the-online-class.com）受講生サポート自動化 — コミュニティチャンネルへのメッセージ送信・フロントコース受講生一括メンション・メンション検知
---

# オンクラス受講生サポート自動化スキル

## 概要

オンクラス（manager.the-online-class.com）のコミュニティ機能を活用した受講生サポート自動化。
チャンネル選択 → フロントエンジニアコース受講生の一括メンション → メッセージ送信、
および @西野鷹也(プロアカ講師) へのメンション検知を行う。

## ログイン情報

| 項目 | 値 |
|---|---|
| URL | `https://manager.the-online-class.com/sign_in` |
| Email | `takaya314boxing@gmail.com` |
| Password | `takaya314` |
| UIフレームワーク | Vuetify 3（v-select, v-list-item, v-field 等） |

## ログインフロー

```
1. https://manager.the-online-class.com/sign_in に遷移
2. メール入力: input[name="email"] (id="input-0", class="v-field__input")
3. パスワード入力: input[name="password"] (id="input-2", class="v-field__input")
4. ボタン: button:has-text("ログインする") (class="v-btn v-btn--block")
5. waitForTimeout(5000) でSPAの読み込み完了を待つ
```

## サイドバー構成（SPAルーティング）

サイドバーは `.v-list-item` で構成。href属性なし（Vue Router内部遷移）。
クリック操作は `scrollIntoView` + `element.click()` をJS経由で実行（Playwright locator.click() はviewport外でタイムアウトする）。

```
ホーム
コース管理
  └ コース一覧
  └ コース招待URL
従業員管理
  └ 従業員一覧  → https://manager.the-online-class.com/accounts
  └ グループ管理
コンテンツ
  └ 記事
  └ アンケート
LP構築
  └ テンプレート構築（ベータ）
  └ CTAボタン
交流
  └ コミュニティ → https://manager.the-online-class.com/community
  └ 感想
  └ お知らせ
マーケティング
  └ マーケティング用公式LINE連携
システム設定
ヘルプ
```

## コミュニティチャンネル一覧（2026-04-03時点）

| # | チャンネル名 | カテゴリ |
|---|---|---|
| 1 | 全体チャンネル | 共通 |
| 2 | もくもく会 | 共通 |
| 3 | 勤怠A - 報告 | 勤怠 |
| 4 | 勤怠B - 報告 | 勤怠 |
| 5 | PDCAアプリ開発 | フロントエンジニア |
| 6 | TodoB - 質問 | フロントエンジニア |
| 7 | TodoB - 報告 | フロントエンジニア |
| 8 | TodoA - 質問 | フロントエンジニア |
| 9 | TodoA - 報告 | フロントエンジニア |
| 10 | クローンチーム | フロントエンジニア |
| 11 | Aチーム（元基礎編） | フロントエンジニア |
| 12 | Bチーム（元Todo） | フロントエンジニア |
| 13 | TechPutチーム1 | フロントエンジニア |

※ メンテ後（2026-04-03）にフリーエンジニア養成コース系チャンネルが削除され、一部チャンネル名が変更（TechPutチーム→TechPutチーム1）

### チャンネル選択セレクタ

```
サイドバーのチャンネルリスト:
  .v-list-item:has-text("チャンネル名")
  → scrollIntoView + click() でチャンネル切替
```

## メッセージ送信

### 入力欄

```
textarea.v-field__input (id="input-7")
→ Vuetify v-textarea コンポーネント
```

### メンション機能

テキストエリアに `@` を入力すると、メンション候補のオートコンプリートが表示される。
候補は `.v-overlay .v-list-item` 内に表示される。

### メンション付きメッセージの送信フロー

```
1. チャンネルを選択
2. textarea に `@` を入力
3. オートコンプリートから対象者を選択（1人ずつ）
4. メッセージ本文を入力
5. 送信（Enter or 送信ボタン）
```

## 従業員一覧（フロントエンジニアコース絞り込み）

### アクセス方法

```
1. https://manager.the-online-class.com/accounts に遷移
2. 「受講コースから絞り込み」の v-select をクリック
   → .v-select .v-field をクリック (force: true)
3. ドロップダウンから「フロントエンジニアコース」を選択
   → .v-overlay .v-list-item:has-text("フロントエンジニアコース")
4. 「従業員検索」ボタンをクリック
5. 結果: 29人の受講生が表示（2026-04-02時点）
```

### 利用可能コース一覧

- フロントエンジニアコース
- 毎日プログラミング基礎ドリル
- フロントエンジニアコース 体験版
- エンジニア起業戦略コース
- フリーエンジニア養成コース
- フリーランスエンジニア養成コースPlus
- アプリ開発体験会
- AIプログラミング体験会コース
- AIプログラミング体験会<画像アップロードシステム開発編>
- アプリ開発体験会 - 特典

## メンション検知（@西野鷹也(プロアカ講師)）

コミュニティの「メンション」タブ（サイドバー下部）を定期的にチェックし、
新しいメンションがあれば通知する。

### 検知フロー

```
1. ログイン
2. コミュニティページに遷移
3. サイドバーの「メンション」をクリック
4. メンション一覧を取得
5. 前回チェック時のタイムスタンプと比較
6. 新規メンションがあれば告知アプリに通知
```

## 告知アプリUI仕様

### チャンネル選択

- **セレクトボックス** → クリックで **チェックボックス付きドロップダウン** が開く
- 複数チャンネルを同時に選択可能
- 選択したチャンネル名はチップ（タグ）で表示
- 「使用停止中」のチャンネルはグレーアウト表示

### 投稿サイトチェック

受講生サポートの新規作成では「オンクラス」のみチェックON。
他の告知サイト（connpass、Peatix等）はチェック対象外。

## 関連ファイル（実装予定）

- `rails-backend/app/services/posting/onclass_service.rb` — 投稿サービス本体
- `rails-backend/app/jobs/post_job.rb` — PostJob に onclass を追加
- `rails-backend/app/models/service_connection.rb` — SERVICES に 'onclass' 追加
- `react-frontend/src/components/PostModal.jsx` — チャンネル選択UI追加

## 技術的注意事項

- **Vuetify SPA**: ページ遷移はVue Router。`page.goto()` 後は `waitForTimeout(5000)` で確実に描画完了を待つ
- **サイドバースクロール**: `.v-list-item` はviewport外の場合がある。`scrollIntoView({ block: 'center' })` + `element.click()` をJS evaluate内で実行
- **v-select**: `.v-select .v-field` を `click({ force: true })` で開き、`.v-overlay .v-list-item:has-text("...")` で選択
- **メンション入力**: `@` 入力後のオートコンプリートは `.v-overlay .v-list-item` に表示される。1人ずつ選択する必要がある
- **ページネーション**: 従業員一覧は10人/ページ、最大79ページ。全員取得には全ページ走査が必要
