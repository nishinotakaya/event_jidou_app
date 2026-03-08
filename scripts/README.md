# こくチーズ フォーム解析スクリプト

## 初回セットアップ

```bash
npx playwright install chromium   # Chromium が無い場合（channel: chrome なら不要）
```

macOS で Google Chrome がインストール済みなら、上記不要でシステム Chrome を使用します。

## バリデーションエラーが出た場合の診断手順

### 1. フォームフィールドのダンプ

実際のフォームにどんな `name` 属性があるか確認します。

```bash
npm run dump-kokuchpro
```

出力: `form-fields-dump.json`（全 input/textarea/select の name 一覧）

### 2. POST データのキャプチャ

送信時のパラメータを取得するには:

```bash
npm run capture-kokuchpro
```

- ブラウザが開き、ログイン→Step1→Step2 まで自動進行
- **手動で** フォームに値を入力して「送信」をクリック
- 30秒以内に送信すると、`captured-post-data.json` に保存されます

### 3. キャプチャしたデータの確認

`captured-post-data.json` を開き、正しいパラメータ名・値を `api/kokuchpro.js` に反映させてください。

## 主な修正ポイント（ api/kokuchpro.js ）

- **概要**: 80文字以内、必須
- **開催日時・募集期間**: CakePHP は `data[EventDate][...][year]`, `[month]`, `[day]` 形式
- **連絡先TEL**: ハイフン必須（例: 03-1234-5678）
