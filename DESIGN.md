# イベント告知アプリ 設計書

## 1. アプリ概要

イベント告知文のテキスト管理・AI添削・画像生成・複数サイトへの自動投稿を一元管理するWebアプリ。

| 項目 | 内容 |
|------|------|
| アプリ名 | イベント告知アプリ |
| 起動 | `npm run web` → http://localhost:3000 |
| 技術スタック | Node.js ESModules / Express / Playwright / Claude API / 画像生成API |
| データ保存 | JSONファイル（`texts/event.json` / `texts/student.json`） |

---

## 2. 機能一覧

| # | 機能 | 状態 |
|---|------|------|
| 1 | テキスト管理（CRUD） | ✅ 実装済み |
| 2 | 複数サイトへの自動投稿 | ✅ 実装済み |
| 3 | **AI添削機能** | 🔲 未実装 |
| 4 | **AI画像生成機能** | 🔲 未実装 |

---

## 3. AI添削機能

### 概要

テキスト管理のイベント告知文を選択し、Claude APIを使って文章を添削・改善する。

### ユーザーフロー

```
1. テキスト一覧のカードに「✨ AI添削」ボタンを追加
2. ボタンを押すと添削モーダルが開く
3. 左側に「現在の文章」、右側に「AI添削後の文章」を表示
4. 気に入ったら「この内容で上書き保存」または「新規として保存」
```

### UI（添削モーダル）

```
┌─────────────────────────────────────────────────────────┐
│ ✨ AI添削                                               │
│                                                         │
│ 添削の方針（任意）:                                      │
│ [簡潔に / 参加意欲を高める / 初心者向けに  ▼]           │
│ または自由入力: [___________________________]           │
│                                                         │
│ ┌──── 現在の文章 ────┐  ┌──── AI添削後 ────────┐     │
│ │ 【10分で？！】AI   │  │ 【AI活用】わずか10分  │     │
│ │ で最強の業務効率化 │  │ で業務効率化アプリを  │     │
│ │ アプリ作成会！     │  │ 作れる！               │     │
│ │                    │  │                        │     │
│ └────────────────────┘  └────────────────────────┘     │
│                                                         │
│ AI添削の改善ポイント:                                    │
│ ・タイトルをより具体的に変更しました                      │
│ ・参加者のベネフィットを冒頭に                           │
│                                                         │
│          [再添削] [上書き保存] [新規保存] [閉じる]       │
└─────────────────────────────────────────────────────────┘
```

### API仕様

#### POST /api/ai/correct

リクエスト:
```json
{
  "content": "添削対象のテキスト",
  "instruction": "簡潔に書き直してください"
}
```

レスポンス:
```json
{
  "corrected": "添削後のテキスト",
  "points": ["改善ポイント1", "改善ポイント2"]
}
```

### 実装仕様（server.js）

```javascript
import Anthropic from '@anthropic-ai/sdk';
const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

app.post('/api/ai/correct', async (req, res) => {
  const { content, instruction } = req.body;

  const message = await anthropic.messages.create({
    model: 'claude-opus-4-6',
    max_tokens: 2048,
    messages: [{
      role: 'user',
      content: `以下のイベント告知文を添削してください。
${instruction ? `方針: ${instruction}` : ''}

【添削対象】
${content}

【出力形式】JSON形式で返してください:
{
  "corrected": "添削後のテキスト",
  "points": ["改善ポイント1", "改善ポイント2"]
}`
    }]
  });

  const result = JSON.parse(message.content[0].text);
  res.json(result);
});
```

### .env 追加項目

```env
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxx
```

### 添削の方針プリセット

| プリセット | 指示内容 |
|-----------|---------|
| 簡潔に | 読みやすく要点を絞って短くまとめる |
| 参加意欲を高める | 参加者のベネフィットを前面に出し、行動を促す |
| 初心者向けに | 専門用語を避け、誰でも参加できる雰囲気にする |
| プロフェッショナルに | ビジネス向けの丁寧な文体に整える |
| SNS向けに | ハッシュタグを追加し短くキャッチーに |

---

## 4. AI画像生成機能

### 概要

イベントタイトル・内容をもとに、告知用のバナー画像をAIで自動生成する。

### ユーザーフロー

```
1. テキスト一覧のカードに「🖼️ 画像生成」ボタンを追加
2. ボタンを押すと画像生成モーダルが開く
3. プロンプト（スタイル・テーマ）をオプションで指定
4. 「生成」ボタンを押すとリアルタイムで画像が表示される
5. 「ダウンロード」または「URLコピー」で画像を取得
```

### UI（画像生成モーダル）

```
┌─────────────────────────────────────────────────────────┐
│ 🖼️ バナー画像生成                                       │
│                                                         │
│ ベースにするテキスト: 標準告知文                         │
│                                                         │
│ スタイル: [プロフェッショナル ▼]                        │
│ カラー:   [ブルー系 ▼]                                  │
│ 追加指示: [____________________________]                │
│                                                         │
│ ┌──────────────────────────────────────┐               │
│ │                                      │               │
│ │           生成された画像              │               │
│ │          1200 × 630 px               │               │
│ │                                      │               │
│ └──────────────────────────────────────┘               │
│                                                         │
│      [再生成] [ダウンロード] [URLコピー] [閉じる]        │
└─────────────────────────────────────────────────────────┘
```

### API仕様

#### POST /api/ai/image

リクエスト:
```json
{
  "content": "バナー生成の元テキスト",
  "style": "プロフェッショナル",
  "color": "ブルー系",
  "extra": "追加の指示"
}
```

レスポンス:
```json
{
  "url": "生成された画像のURL",
  "prompt": "実際に使用したプロンプト"
}
```

### 実装仕様（server.js）

```javascript
import OpenAI from 'openai';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

app.post('/api/ai/image', async (req, res) => {
  const { content, style, color, extra } = req.body;

  // イベントタイトルを抽出
  const title = content.split('\n')[0].replace(/^[#【\s]+/, '').slice(0, 60);

  const prompt = `
    Event announcement banner image for: "${title}".
    Style: ${style || 'professional and modern'}.
    Color scheme: ${color || 'blue and white'}.
    ${extra || ''}
    Text-free design. 1200x630px. High quality.
  `.trim();

  const response = await openai.images.generate({
    model: 'dall-e-3',
    prompt,
    n: 1,
    size: '1792x1024',
    quality: 'standard',
  });

  res.json({
    url: response.data[0].url,
    prompt,
  });
});
```

### .env 追加項目

```env
OPENAI_API_KEY=sk-xxxxxxxxxxxxx
```

### スタイルプリセット

| スタイル | 説明 |
|---------|------|
| プロフェッショナル | ビジネス向けのクリーンなデザイン |
| カジュアル | 親しみやすいポップなデザイン |
| テック系 | デジタル・IT感のある近未来的デザイン |
| ミニマル | シンプルで余白の多いデザイン |

---

## 5. ファイル構成（追加後）

```
イベント 自動告知用/
├── server.js              ← API追加（/api/ai/correct, /api/ai/image）
├── public/
│   ├── index.html         ← 添削・画像生成ボタン追加
│   ├── style.css          ← 新モーダルのスタイル追加
│   └── app.js             ← 添削・画像生成モーダルのロジック追加
├── texts/
│   ├── event.json
│   └── student.json
├── .env                   ← ANTHROPIC_API_KEY, OPENAI_API_KEY 追加
├── DESIGN.md              ← この設計書
└── package.json           ← @anthropic-ai/sdk, openai パッケージ追加
```

---

## 6. package.json 追加パッケージ

```bash
npm install @anthropic-ai/sdk openai
```

---

## 7. 実装の優先順位

| 優先度 | 機能 | 理由 |
|-------|------|------|
| 高 | AI添削 | テキストの質向上に直結・APIコストが低い |
| 中 | 画像生成 | 告知の訴求力向上・DALL-E APIコスト要注意 |

---

## 8. 注意事項

- `ANTHROPIC_API_KEY` と `OPENAI_API_KEY` は `.env` で管理（コードに直書き禁止）
- 画像生成はDALL-E 3で1枚あたり約$0.04（standard）かかるため、連打防止のローディング制御を実装すること
- 添削結果はあくまでAIの提案。最終確認は必ず人間が行う
