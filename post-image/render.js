// satori(SVG) → resvg(PNG) のレンダリングパイプライン。
// Heroku でも動く（headless ブラウザ不要・ピュア JS / native binding）。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import satori from 'satori';
import { Resvg } from '@resvg/resvg-js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// フォントは起動時に 1 回だけ読む。
// ⚠️ 本番では Noto Sans JP を必要字種にサブセットして同梱する（フルだと数 MB で重い）。
const FONTS = [
  { name: 'NotoSansJP-Regular', weight: 400, style: 'normal', path: 'fonts/NotoSansJP-Regular.ttf' },
  { name: 'NotoSansJP-Bold', weight: 700, style: 'normal', path: 'fonts/NotoSansJP-Bold.ttf' },
].map((f) => ({ ...f, data: fs.readFileSync(path.join(__dirname, f.path)) }));

// IG フィード 4:5（カルーセルもこの比率で統一）。X は 16:9 等に変えてよい。
export const SIZES = {
  ig_portrait: { width: 1080, height: 1350 },
  ig_square: { width: 1080, height: 1080 },
  x_landscape: { width: 1600, height: 900 },
};

/**
 * VDOM(satori ツリー) → PNG Buffer
 * @param {object} node  templates.js が返す {type, props} ツリー
 * @param {{width:number,height:number}} size
 * @returns {Promise<Buffer>}
 */
export async function renderToPng(node, size = SIZES.ig_portrait) {
  const svg = await satori(node, {
    width: size.width,
    height: size.height,
    fonts: FONTS.map(({ name, data, weight, style }) => ({ name, data, weight, style })),
  });
  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: size.width } });
  return resvg.render().asPng();
}
