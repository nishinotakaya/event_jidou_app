# Vercel デプロイ手順

## ⚠️ 重要な制限

Vercel では以下の制限があります：

- **投稿機能（こくチーズ・Peatix等）**: Playwright（ブラウザ自動操作）は Vercel 上で動作しません
- **テキスト保存**: ファイル保存（texts/*.json）は Vercel の読み取り専用環境のため永続化されません
- **動作する機能**: AI（文章自動生成・添削・エージェント）、Web UI の表示

フル機能が必要な場合は Railway や Render でのデプロイを検討してください。

---

## 1. Vercel CLI のインストール

```bash
npm i -g vercel
```

## 2. デプロイ

```bash
cd "/Users/nishinotakaya/イベント 自動告知用"
vercel
```

初回はログインやプロジェクト名の入力が求められます。

本番デプロイ：

```bash
vercel --prod
```

## 3. 環境変数の設定

Vercel ダッシュボードで設定するか、CLI で追加：

```bash
vercel env add OPENAI_API_KEY
vercel env add CONPASS__KOKUCIZE_MAIL
vercel env add CONPASS_KOKUCIZE_PASSWORD
vercel env add PEATIX_EMAIL
vercel env add PEATIX_PASSWORD
vercel env add TECHPLAY_EMAIL
vercel env add TECHPLAY_PASSWORD
```

### 環境変数一覧

| 変数名 | 説明 | 必須 |
|--------|------|------|
| `OPENAI_API_KEY` | OpenAI API キー（文章生成・添削用） | AI利用時 |
| `CONPASS__KOKUCIZE_MAIL` | connpass / こくチーズ ログイン用メール | 投稿時 |
| `CONPASS_KOKUCIZE_PASSWORD` | connpass / こくチーズ パスワード | 投稿時 |
| `PEATIX_EMAIL` | Peatix メール | 投稿時 |
| `PEATIX_PASSWORD` | Peatix パスワード | 投稿時 |
| `TECHPLAY_EMAIL` | TechPlay メール | 投稿時 |
| `TECHPLAY_PASSWORD` | TechPlay パスワード | 投稿時 |

### ダッシュボードでの設定

1. [vercel.com](https://vercel.com) にログイン
2. プロジェクトを選択
3. **Settings** → **Environment Variables**
4. 各変数を追加（Production / Preview / Development で適用範囲を選択）

---

## 4. 環境変数を一括で設定する例（CLI）

```bash
# 対話式で1つずつ追加
vercel env add OPENAI_API_KEY production
vercel env add CONPASS__KOKUCIZE_MAIL production
vercel env add CONPASS_KOKUCIZE_PASSWORD production
vercel env add PEATIX_EMAIL production
vercel env add PEATIX_PASSWORD production
vercel env add TECHPLAY_EMAIL production
vercel env add TECHPLAY_PASSWORD production
```

---

## 5. 再デプロイ（環境変数変更後）

```bash
vercel --prod
```
