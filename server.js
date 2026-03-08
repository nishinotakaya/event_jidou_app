import express from 'express';
import { readFile, writeFile } from 'fs/promises';
import { existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';
dotenv.config();

import * as kokuchpro from './kokuchpro.js';
import * as peatix from './peatix.js';
import * as techplay from './techplay.js';
import * as connpass from './connpass.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
app.use(express.json());
app.use(express.static(join(__dirname, 'public')));

const FILES = {
  event:   join(__dirname, 'texts/event.json'),
  student: join(__dirname, 'texts/student.json'),
};

async function load(type) {
  if (!existsSync(FILES[type])) return [];
  return JSON.parse(await readFile(FILES[type], 'utf-8'));
}
async function save(type, data) {
  await writeFile(FILES[type], JSON.stringify(data, null, 2), 'utf-8');
}
function today() { return new Date().toISOString().slice(0, 10); }
function nextId(data, type) {
  const prefix = type === 'event' ? 'event_' : 'student_';
  const nums = data.map(d => parseInt(d.id.replace(prefix, ''), 10)).filter(n => !isNaN(n));
  return `${prefix}${String((nums.length ? Math.max(...nums) : 0) + 1).padStart(3, '0')}`;
}

// ===== テキスト CRUD =====
app.get('/api/texts/:type', async (req, res) => res.json(await load(req.params.type)));

app.post('/api/texts/:type', async (req, res) => {
  const { type } = req.params;
  const { name, content } = req.body;
  const data = await load(type);
  const now = today();
  const item = { id: nextId(data, type), name, type, content, createdAt: now, updatedAt: now };
  data.push(item);
  await save(type, data);
  res.json(item);
});

app.put('/api/texts/:type/:id', async (req, res) => {
  const { type, id } = req.params;
  const { name, content } = req.body;
  const data = await load(type);
  const idx = data.findIndex(d => d.id === id);
  if (idx === -1) return res.status(404).json({ error: 'Not found' });
  data[idx] = { ...data[idx], name, content, updatedAt: today() };
  await save(type, data);
  res.json(data[idx]);
});

app.delete('/api/texts/:type/:id', async (req, res) => {
  const { type, id } = req.params;
  const data = await load(type);
  const idx = data.findIndex(d => d.id === id);
  if (idx === -1) return res.status(404).json({ error: 'Not found' });
  data.splice(idx, 1);
  await save(type, data);
  res.json({ ok: true });
});

// ===== サイトハンドラーマップ（UIのサイト名 → モジュール） =====
const SITE_HANDLERS = {
  'こくチーズ': kokuchpro,
  'Peatix':     peatix,
  'connpass':   connpass,
  'techplay':   techplay,
};

// ===== SSEで投稿実行（headless・バックグラウンド） =====
app.post('/api/post', async (req, res) => {
  const { content, sites, eventFields } = req.body;

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const send = (data) => { if (!res.writableEnded) res.write(`data: ${JSON.stringify(data)}\n\n`); };
  const log  = (msg)  => { console.log(msg); send({ type: 'log', message: msg }); };

  if (!sites?.length) {
    send({ type: 'error', message: '投稿先が選択されていません' });
    return res.end();
  }

  let browser;
  try {
    const { chromium } = await import('playwright');
    log('🚀 バックグラウンドでブラウザ起動中...');

    browser = await chromium.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
    });

    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
      locale: 'ja-JP',
      viewport: { width: 1280, height: 800 },
    });
    const page = await context.newPage();

    for (const site of sites) {
      send({ type: 'status', site, status: 'running', message: '処理中...' });
      try {
        const handler = SITE_HANDLERS[site];
        if (!handler) throw new Error(`未対応のサイト: ${site}`);

        await handler.post(page, content, eventFields || {}, log);
        send({ type: 'status', site, status: 'success', message: '✅ 完了' });
      } catch (err) {
        log(`[${site}] ❌ ${err.message}`);
        send({ type: 'status', site, status: 'error', message: err.message });
        await page.goto('about:blank').catch(() => {});
      }
    }

    log('✅ 全サイト処理完了');
    send({ type: 'done' });
  } catch (err) {
    log(`❌ 致命的エラー: ${err.message}`);
    send({ type: 'error', message: err.message });
  } finally {
    if (browser) await browser.close().catch(() => {});
    res.end();
  }
});

app.listen(3000, () => console.log('✅ サーバー起動: http://localhost:3000'));
