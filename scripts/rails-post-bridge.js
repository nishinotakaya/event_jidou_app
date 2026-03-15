/**
 * Rails の PostController から呼ばれるブリッジスクリプト
 * 引数: ペイロードJSONファイルのパス
 * 出力: JSON Lines（各行が SSE イベント相当のJSONオブジェクト）
 */
import 'dotenv/config';
import { readFile } from 'fs/promises';
import { chromium } from 'playwright';

import * as kokuchpro from '../api/kokuchpro.js';
import * as peatix     from '../api/peatix.js';
import * as connpass   from '../api/connpass.js';
import * as techplay   from '../api/techplay.js';
import * as lme        from '../api/lme.js';

const SITE_HANDLERS = {
  'こくチーズ': kokuchpro,
  'Peatix':     peatix,
  'connpass':   connpass,
  'techplay':   techplay,
  'LME':        lme,
};

function emit(data) {
  process.stdout.write(JSON.stringify(data) + '\n');
}

const log  = (msg) => emit({ type: 'log', message: msg });
const send = (data) => emit(data);

(async () => {
  const payloadPath = process.argv[2];
  if (!payloadPath) { emit({ type: 'error', message: 'payload file path required' }); process.exit(1); }

  const payload = JSON.parse(await readFile(payloadPath, 'utf-8'));
  const { content, sites, eventFields, openaiApiKey } = payload;

  let browser;
  try {
    log('🚀 バックグラウンドでブラウザ起動中...');
    browser = await chromium.launch({
      headless: true,
      ...(process.platform === 'darwin' && { channel: 'chrome' }),
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    log(`🚀 ${sites.length}サイトを並列投稿開始...`);

    await Promise.all(sites.map(async (site) => {
      const ctx  = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/145.0.0.0 Safari/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      });
      const page = await ctx.newPage();
      send({ type: 'status', site, status: 'running', message: '処理中...' });
      try {
        const handler = SITE_HANDLERS[site];
        if (!handler) throw new Error(`未対応のサイト: ${site}`);
        await handler.post(page, content, { ...eventFields }, log);
        send({ type: 'status', site, status: 'success', message: '✅ 完了' });
      } catch (err) {
        log(`[${site}] ❌ ${err.message}`);
        send({ type: 'status', site, status: 'error', message: err.message });
      } finally {
        await ctx.close().catch(() => {});
      }
    }));

    log('✅ 全サイト処理完了');
    send({ type: 'done' });
  } catch (err) {
    emit({ type: 'error', message: err.message });
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
})();
