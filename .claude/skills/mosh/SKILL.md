---
name: mosh
description: MOSH解析結果 — REST JSON API（backend.api.mosh.jp）。サービス作成はログイン後に解析必要
---

# MOSH（mosh.jp）解析結果

## 概要

個人のサービスをオンライン販売できるプラットフォーム。

## API仕様（解析済み）

- **認証API**: `POST backend.api.mosh.jp/auth/sessions` (JSON `{email, password}`)
- **データAPI**: `rest.mosh.jp`
- **CSRFトークン**: なし（JSON API）
- **ソーシャルログイン**: Google, Apple

## 発見したエンドポイント

| メソッド | エンドポイント | 用途 |
|---------|-------------|------|
| POST | `backend.api.mosh.jp/auth/sessions` | ログイン |
| GET | `rest.mosh.jp/hosts/host/services` | サービス一覧 |
| GET | `rest.mosh.jp/legacy/hosts/creator` | クリエイター情報 |
| GET | `rest.mosh.jp/hosts/{hostId}/services` | ホスト別サービス |

## 実装ステータス: 未実装

パスワード`Takaya314!`でログイン不可（422エラー）。正しいパスワードで再解析必要。
