# SNSアカウント プロフィール設定

## 対象プラットフォーム

- Facebook
- Instagram（プロアカウント：ビジネス）

## アカウント認証情報

**`.env` で一元管理**（このファイルには機密情報を書かない）。

| 変数名 | 用途 |
|---|---|
| `FACEBOOK_EMAIL` | Facebook ログインメール |
| `FACEBOOK_PASSWORD` | Facebook パスワード |
| `INSTAGRAM_EMAIL` | Instagram ログインメール |
| `INSTAGRAM_PASSWORD` | Instagram パスワード |

実値は `.env`（gitignore済み）を参照。

## プロフィール

- **名前**: AIエンジニア 西野
- **肩書き**: 講師 / エンジニア教育
- **プロフィール画像**: `nishino_.png`（リポジトリルートに配置済み）

![プロフィール画像](../../nishino_.png)

---

## 自己紹介文（コピペ用）

### 🟢 Instagram 用（推奨：改行あり）

```
元介護士で、今はAIエンジニアしてます。
講師やエンジニア教育もやってます。

介護士 月収12万円 → AIエンジニア 月収70万円

未経験からの学び方や転職のことを発信してます。
```

### 🐦 X（Twitter）用（1行連結）

```
元介護士で、今はAIエンジニアしてます。講師やエンジニア教育もやってます。介護士 月収12万円 → AIエンジニア 月収70万円。未経験からの学び方や転職のことを発信してます。
```

### ✨ バランス版（最推奨）

```
元介護士で、今はAIエンジニアしてます。
講師やエンジニア教育もしてます。
介護士 月収12万円 → AIエンジニア 月収70万円
未経験からの学び方や転職について発信してます。
```

### 🫧 ラフ版（やや砕けた調子）

```
元介護士です。今はAIエンジニアしてます。
講師やエンジニア教育もしてます。

介護士 月収12万円 → AIエンジニア 月収70万円

未経験からの学び方とか、転職のことを発信してます。
```

---

## 次アクション

- [ ] Facebook ページ作成 → Meta for Developers App 登録 → Page Access Token 取得
- [ ] Instagram プロアカウント化（ビジネス/クリエイター）→ Facebook ページと連携
- [ ] `.env` に `FACEBOOK_EMAIL` / `FACEBOOK_PASSWORD` / `FACEBOOK_PAGE_ID` / `FACEBOOK_PAGE_ACCESS_TOKEN` を追加
- [ ] `service_connections` テーブルに facebook / instagram_business を追加
- [ ] このファイルから認証情報を削除、`.env` 側一本化
