---
name: pando
description: Pando解析結果 — CakePHP HTMLフォーム + Froala Editor。活動記録プラットフォーム（イベント告知ではない）
---

# Pando（pando.life）解析結果

## 概要

学生・社会人の活動記録・プロフィールプラットフォーム。イベント告知ではなく「活動・所属」の記録。

## API仕様（解析済み）

- **方式**: HTMLフォームPOST（CakePHP）
- **認証**: Cookie `ps_`（httpOnly, secure）
- **CSRFトークン**: あり（CakePHP形式: `data[_Token][key]`, `data[_Token][fields]`）
- **リッチテキスト**: Froala Editor（4つのtextarea）

## ログインAPI

```
POST https://pando.life/login
Content-Type: application/x-www-form-urlencoded
data[MyApp_Front_InputForm_Login][email]=xxx
data[MyApp_Front_InputForm_Login][password]=xxx
data[_Token][key]=xxx
```

## 活動作成フォーム（/mypage/work/add）

- `data[MyApp_InputForm_AccountWork][title]` — タイトル（必須）
- `data[MyApp_InputForm_AccountWork][contentsRole]` — 内容・役割（Froala、必須）
- `data[MyApp_InputForm_AccountWork][contentsMeaning]` — 活動の意義（Froala、必須）
- `data[MyApp_InputForm_AccountWork][contentsDesire]` — 想い・やりがい（Froala、必須）
- `data[MyApp_InputForm_AccountWork][contentsAchieve]` — 実現したいこと（Froala、必須）

## 実装ステータス: 未実装（イベント告知プラットフォームではないため優先度低）
