// Phase 0 技術検証: 日本語が「豆腐(□)」にならない PNG を実際に出す。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderToPng, SIZES } from './render.js';
import { singleCard, carouselCover } from './templates.js';
import tokens from './tokens.json' with { type: 'json' };

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const out = (name) => path.join(__dirname, 'out', name);

const samples = [
  {
    file: 'single_midnight.png',
    size: SIZES.ig_portrait,
    node: singleCard({
      theme: tokens.themes.midnight,
      tokens,
      kicker: '副業エンジニアの現実',
      title: '未経験から月10万円。\n最初の壁は「営業」だった。',
    }),
  },
  {
    file: 'cover_mint.png',
    size: SIZES.ig_portrait,
    node: carouselCover({
      theme: tokens.themes.mint,
      tokens,
      page: '01',
      title: 'AIで時短する\nエンジニアの\n副業ルーティン7選',
    }),
  },
  {
    file: 'single_paper.png',
    size: SIZES.ig_square,
    node: singleCard({
      theme: tokens.themes.paper,
      tokens,
      kicker: 'TIPS',
      title: 'コードは書けるのに\n稼げない人へ。',
    }),
  },
];

for (const s of samples) {
  const png = await renderToPng(s.node, s.size);
  fs.writeFileSync(out(s.file), png);
  console.log(`✓ ${s.file}  (${s.size.width}x${s.size.height}, ${(png.length / 1024).toFixed(0)} KB)`);
}
console.log('done →', path.join(__dirname, 'out'));
