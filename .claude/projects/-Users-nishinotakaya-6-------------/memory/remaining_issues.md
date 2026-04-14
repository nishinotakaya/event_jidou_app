---
name: 残課題一覧 2026-04-12
description: 本番環境で確認された未解決バグ・機能要望のリスト
type: project
---

## 解決済み（2026-04-12）
- Doorkeeper参加者数: API v2 + キャッシュクリア
- Peatix参加者数: peatix-api.com/v4 + Bearer token (localStorage)
- WebSocket: Vercel→Heroku直接接続(wss://)
- Playwright Debugger NameError: initializer stub
- Redis接続数83%→13%: Sidekiq並列2, pool縮小
- 手動URL入力: 投稿タグクリック→URL入力ダイアログ
- 全サイトタグ表示: 未投稿も含めて常時表示

## 本番環境バグ（優先度順）

1. **参加者DB保存＋モーダル表示** — 要件:
   - `event_participants` テーブル新設（item_id, site_name, name, email, created_at）
   - 「👥 参加者確認」で各サイトから取得 → DB保存
   - 「🔄 参加者同期」ボタンで最新化
   - タグクリック → モーダルで参加者名一覧表示
   - Peatix: API取得済み（peatix-api.com/v4 Bearer）✅
   - こくチーズ: チケット種別行を誤カウント（0/10なのに4表示）→ パーサー修正必要
   - Doorkeeper/connpass/TechPlay: Playwright経由で取得（既存コードあり）
2. **同期（sync）タイムアウト** — 30秒H12エラー。バックグラウンドジョブ化が必要
4. **オンクラスチャンネル選択** — 本番headlessでコミュニティのチャンネルリストが読み込まれない（メインナビが表示される）
5. **つなゲート投稿の日時入力** — textarea修正済みだが日時・場所・定員の入力が本番headlessで未検証
6. **セミナーBiZ フリープラン上限** — 公開中1件まで。既存イベントの更新（update）で回避するか有料プラン
7. **全イベント一括参加者チェック** — 未実装。ユーザー要望あり
8. **Facebook/Instagram/Threads投稿** — サービス登録済みだがブラウザログイン（セッション取得）未完了
9. **ローカルセッション→本番DB同期の仕組み化** — 現在は手動base64コピー。EventRegist/つなゲートのGoogleセッション共有を自動化すべき

## 機能要望

- 月ナビゲーション（実装済み・フロントのみ）
- 受講期限表示（実装済み・デプロイ済み）
- 画像ギャラリー（実装済み・デプロイ済み）
- 再投稿ボタン（実装済み・デプロイ済み）
- プラン制限表示（実装済み・デプロイ済み）
- 新ポータルサイト追加（セミナー情報.com / MOSH）— リサーチ済み・未実装

## 根本対策の提案

**Why:** Heroku Eco (512MB) + headless Chromium は本質的に不安定。メモリ不足でクラッシュ、セレクタ不一致、タイムアウトが頻発。
**How to apply:** Standard-2X (1GB) へのアップグレード、またはPlaywright依存を減らしてAPI直接呼び出しに移行（Peatix Bearer API, connpass fetch API等）。
