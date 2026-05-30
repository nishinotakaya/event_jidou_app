# post-image — 綺麗な投稿画像レンダラ（beautiful-posts Phase 0）

HTML/CSS テンプレ → `satori`(SVG) → `@resvg/resvg-js`(PNG)。
headless ブラウザ不要なので **Heroku dyno でもローカルでも動く**。設計は `.claude/skills/beautiful-posts/SKILL.md`。

## セットアップ

```bash
cd post-image
npm install
# フォント取得（リポジトリには含めない。本番は必要字種にサブセットして同梱する）
mkdir -p fonts
curl -sL -o fonts/NotoSansJP-Regular.otf "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@main/Sans/OTF/Japanese/NotoSansJP-Regular.otf"
curl -sL -o fonts/NotoSansJP-Bold.otf    "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@main/Sans/OTF/Japanese/NotoSansJP-Bold.otf"
npm run demo   # out/ に PNG を 3 枚出力
```

## 構成

| ファイル | 役割 |
|---|---|
| `tokens.json` | デザイントークン（テーマ色 / フォント / 余白 / ブランド）。ブランドの単一の真実 |
| `templates.js` | satori テンプレ（`singleCard` / `carouselCover`）。CSS は flexbox のみ |
| `render.js` | `renderToPng(node, size)` — satori→resvg。`SIZES` に IG 4:5 / 正方形 / X 16:9 |
| `demo.js` | Phase 0 検証。日本語が豆腐(□)にならない PNG を出力 |

## Phase 0 で確認したこと

- ✅ Noto Sans JP 同梱で **日本語が豆腐にならず**レンダリングされる
- ✅ 1080×1350(4:5) / 1080×1080 で 60〜80KB の PNG を出力
- ✅ 簡易オートフィット（文字数でフォントサイズ段階調整）

## 次（Phase 1 以降）

- フォントを**サブセット**化（9MB → 数百 KB）
- Cloudinary へアップロードして URL 化 → 既存 X / IG 投稿に接続
- コピー生成（OpenAI, format 別）+ フロントのプレビュー承認 UI
- カルーセル本文テンプレ（`carouselBody`）
