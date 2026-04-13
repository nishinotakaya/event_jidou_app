---
name: aini
description: aini（旧TABICA）解析結果 — GraphQL API + reCAPTCHA v2 invisible。体験作成は/me/travels/new
---

# aini（helloaini.com）解析結果

## 概要

体験型イベント・ワークショップのマッチングプラットフォーム。

## API仕様（解析済み）

- **API方式**: GraphQL（`POST /graphql`）
- **認証**: Cookie `tabica_session`（httpOnly, secure）
- **reCAPTCHA**: v2 invisible（サイトキー: `6LfDOnkUAAAAAOodphQGnjQoCR7201nejG-4A5h_`）
- **ソーシャルログイン**: Facebook, LINE, Google

## ログインAPI

```graphql
mutation SignInUserMutation($mail: String!, $password: String!, $recaptchaToken: String, $code: String, $codeHash: String) {
  signInUserMutation(input: {mail: $mail, password: $password, recaptchaToken: $recaptchaToken, code: $code, codeHash: $codeHash}) {
    success redirectUrl codeHash __typename
  }
}
```

## ページURL

| ページ | URL |
|--------|-----|
| ログイン | `/signin` |
| ダッシュボード | `/me/dashboard` |
| 体験作成 | `/me/travels/new` |
| 体験管理 | `/me/travels` |
| ホスト申請 | `/me/settings/account/apply/host_confirm` |

## 実装ステータス: 未実装

認証情報（`takaya314boxing@gmail.com` / `Takaya314!!`）でログイン失敗。reCAPTCHA or パスワード要確認。
