---
name: instagram
description: Instagram投稿自動化 — Playwright方式。画像必須・キャプション入力・シェアの全ステップ完了
---

# Instagram投稿自動化スキル

## 概要

Instagramへのイベント告知投稿。Playwright方式（画像必須）。

## アーキテクチャ

- **方式**: Playwright（ブラウザ自動操作）— API化不可（Meta APIは審査が厳しい）
- **認証**: ID/PW + keyboard.type入力（fillは動作しない）
- **サービスファイル**: `app/services/posting/instagram_service.rb`

## 投稿フロー

```
1. ログイン
   - instagram.com → Cookieセッション復元
   - 失敗時: keyboard.typeでメール/パスワード入力 → Enterキー
   - 通知ダイアログ「後で」スキップ

2. 新規投稿
   - svg[aria-label="新しい投稿"] をJSクリック（aria-labelは「新しい投稿」）
   - input[type="file"] で画像アップロード（DALL-E画像必須）

3. 次へボタン（×2回）
   - div[role="dialog"]内のbutton/div[role="button"]を探す
   - テキスト「次へ」でマッチ → JSクリック（overlay回避）

4. キャプション入力
   - div[role="dialog"] [aria-label*="キャプション"] を探す
   - keyboard.typeで入力（delay: 5ms）

5. シェア
   - div[role="dialog"]内の「シェア」ボタンをJSクリック
   - 10秒待機 → 「投稿がシェアされました。」確認
```

## キャプション構成

```
タイトル

📅 日付 時間
💻 オンライン開催

本文（最初の5行）

📌 お申し込みはこちら
[イベントURL]

#イベント #生成AI #プログラミング #エンジニア #転職 #スキルアップ #オンラインセミナー
```

最大2200文字。

## 重要な知見

- `fill`ではなく`keyboard.type`を使う（Reactフォーム対応）
- 「新しい投稿」のaria-labelは「新規投稿」ではない
- 「次へ」「シェア」ボタンは`div[role="button"]`（`button`ではない）
- 画像必須（テキストのみ投稿は不可）

## 環境変数

- `INSTAGRAM_EMAIL` / `INSTAGRAM_PASSWORD`

## 本番テスト: ✅ ローカルテスト成功（投稿確認済み）
