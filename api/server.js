import express from 'express';
import { readFile, writeFile, unlink } from 'fs/promises';
import { existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';
dotenv.config();

import * as kokuchpro from './kokuchpro.js';
import * as peatix from './peatix.js';
import * as techplay from './techplay.js';
import * as connpass from './connpass.js';
import * as lme from './lme.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = join(__dirname, '..');
const app = express();
app.use(express.json());
app.use(express.static(join(rootDir, 'public')));

const FILES = {
  event:   join(rootDir, 'texts/event.json'),
  student: join(rootDir, 'texts/student.json'),
};

async function load(type) {
  if (!existsSync(FILES[type])) return [];
  return JSON.parse(await readFile(FILES[type], 'utf-8'));
}
async function save(type, data) {
  await writeFile(FILES[type], JSON.stringify(data, null, 2), 'utf-8');
}

// ===== フォルダ管理 =====
const FOLDER_FILES = {
  event:   join(rootDir, 'texts/event-folders.json'),
  student: join(rootDir, 'texts/student-folders.json'),
};
async function loadFolders(type) {
  if (!existsSync(FOLDER_FILES[type])) return [];
  return JSON.parse(await readFile(FOLDER_FILES[type], 'utf-8'));
}
async function saveFolders(type, data) {
  await writeFile(FOLDER_FILES[type], JSON.stringify(data, null, 2), 'utf-8');
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
  const { name, content, folder = '' } = req.body;
  const data = await load(type);
  const now = today();
  const item = { id: nextId(data, type), name, type, content, folder, createdAt: now, updatedAt: now };
  data.push(item);
  await save(type, data);
  res.json(item);
});

app.put('/api/texts/:type/:id', async (req, res) => {
  const { type, id } = req.params;
  const { name, content, folder } = req.body;
  const data = await load(type);
  const idx = data.findIndex(d => d.id === id);
  if (idx === -1) return res.status(404).json({ error: 'Not found' });
  data[idx] = { ...data[idx], name, content, ...(folder !== undefined && { folder }), updatedAt: today() };
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

// ===== フォルダ CRUD =====
app.get('/api/folders/:type', async (req, res) => res.json(await loadFolders(req.params.type)));

app.post('/api/folders/:type', async (req, res) => {
  const { type } = req.params;
  const { name } = req.body;
  if (!name) return res.status(400).json({ error: 'name required' });
  const folders = await loadFolders(type);
  if (folders.includes(name)) return res.status(409).json({ error: 'already exists' });
  folders.push(name);
  await saveFolders(type, folders);
  res.json({ ok: true, folders });
});

app.delete('/api/folders/:type/:name', async (req, res) => {
  const { type, name: rawName } = req.params;
  const name = decodeURIComponent(rawName);
  const folders = await loadFolders(type);
  await saveFolders(type, folders.filter(f => f !== name));
  // そのフォルダのアイテムを未分類に戻す
  const items = await load(type);
  items.forEach(item => { if (item.folder === name) item.folder = ''; });
  await save(type, items);
  res.json({ ok: true });
});

// ===== サイトハンドラーマップ（UIのサイト名 → モジュール） =====
const SITE_HANDLERS = {
  'こくチーズ': kokuchpro,
  'Peatix':     peatix,
  'connpass':   connpass,
  'techplay':   techplay,
  'LME':        lme,
};

// ===== SSEで投稿実行（headless・バックグラウンド） =====
app.post('/api/post', async (req, res) => {
  const { content, sites, eventFields, generateImage, imageStyle, openaiApiKey } = req.body;

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

  // ===== 画像自動生成 =====
  let imagePath = null;
  if (generateImage) {
    const key = openaiApiKey || process.env.OPENAI_API_KEY;
    if (!key) {
      send({ type: 'log', message: '⚠️ 画像生成: OpenAI APIキーが設定されていません。スキップします。' });
    } else {
      try {
        send({ type: 'log', message: '🖼️ DALL-E 3で画像生成中...' });
        const OpenAI = (await import('openai')).default;
        const openai = new OpenAI({ apiKey: key });
        const imageTitle = eventFields?.title || content.split('\n')[0].slice(0, 80) || 'イベント';
        const isCute = (imageStyle || 'cute') === 'cute';
        const stylePrompt = isCute
          ? `Cute and kawaii style event banner for "${imageTitle}". Pastel colors, soft watercolor illustration, adorable characters or flowers, warm and friendly atmosphere. No text. High quality.`
          : `Cool and stylish event banner for "${imageTitle}". Bold colors, modern geometric design, dynamic composition, sharp and professional look. No text. High quality.`;
        send({ type: 'log', message: `🖼️ スタイル: ${isCute ? '🌸 可愛い系' : '⚡ かっこいい系'}` });
        const imgResponse = await openai.images.generate({
          model: 'dall-e-3',
          prompt: stylePrompt,
          n: 1,
          size: '1024x1024',
        });
        const imageUrl = imgResponse.data[0].url;
        send({ type: 'log', message: `🖼️ 画像URL取得完了。ダウンロード中...` });
        const dlRes = await fetch(imageUrl);
        const buffer = Buffer.from(await dlRes.arrayBuffer());
        imagePath = join(rootDir, `event_image_${Date.now()}.png`);
        await writeFile(imagePath, buffer);
        send({ type: 'log', message: `🖼️ 画像生成・保存完了` });
      } catch (err) {
        send({ type: 'log', message: `⚠️ 画像生成失敗: ${err.message}` });
      }
    }
  }

  let browser;
  try {
    const { chromium } = await import('playwright');
    log('🚀 バックグラウンドでブラウザ起動中...');

    browser = await chromium.launch({
      headless: true,
      ...(process.platform === 'darwin' && { channel: 'chrome' }),
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
    });

    // サイトごとに独立したコンテキスト＆ページを作成して並列実行
    log(`🚀 ${sites.length}サイトを並列投稿開始...`);

    await Promise.all(sites.map(async (site) => {
      const siteContext = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
        locale: 'ja-JP',
        viewport: { width: 1280, height: 800 },
      });
      const sitePage = await siteContext.newPage();
      send({ type: 'status', site, status: 'running', message: '処理中...' });
      try {
        const handler = SITE_HANDLERS[site];
        if (!handler) throw new Error(`未対応のサイト: ${site}`);

        await handler.post(sitePage, content, { ...eventFields, imagePath }, log);
        send({ type: 'status', site, status: 'success', message: '✅ 完了' });
      } catch (err) {
        log(`[${site}] ❌ ${err.message}`);
        send({ type: 'status', site, status: 'error', message: err.message });
      } finally {
        await siteContext.close().catch(() => {});
      }
    }));

    log('✅ 全サイト処理完了');
    send({ type: 'done' });
  } catch (err) {
    log(`❌ 致命的エラー: ${err.message}`);
    send({ type: 'error', message: err.message });
  } finally {
    if (browser) await browser.close().catch(() => {});
    if (imagePath) await unlink(imagePath).catch(() => {});
    res.end();
  }
});

// ===== AI（添削・エージェント） =====
app.post('/api/ai/correct', async (req, res) => {
  try {
    const { text, apiKey } = req.body;
    const key = apiKey || process.env.OPENAI_API_KEY;
    if (!key) return res.status(400).json({ error: 'OpenAI APIキーを入力してください' });
    if (!text?.trim()) return res.status(400).json({ error: 'テキストを入力してください' });

    const OpenAI = (await import('openai')).default;
    const openai = new OpenAI({ apiKey: key });
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: 'あなたは文章添削のプロです。入力されたテキストを、誤字脱字の修正・表現の改善・読みやすさの向上を行い、改善版を返してください。元の意図やトーンは保ちつつ、より伝わりやすい文章にしてください。改善版のみを返し、説明は不要です。' },
        { role: 'user', content: text },
      ],
      temperature: 0.3,
    });
    const result = completion.choices[0]?.message?.content?.trim() || text;
    res.json({ corrected: result });
  } catch (err) {
    res.status(500).json({ error: err.message || '添削に失敗しました' });
  }
});

app.post('/api/ai/generate', async (req, res) => {
  try {
    const { title, type, apiKey, eventDate, eventTime, eventEndTime } = req.body;
    console.log(`[generate] eventDate="${eventDate}" eventTime="${eventTime}" eventEndTime="${eventEndTime}"`);
    const key = apiKey || process.env.OPENAI_API_KEY;
    if (!key) return res.status(400).json({ error: 'OpenAI APIキーを入力してください' });
    if (!title?.trim()) return res.status(400).json({ error: '名前（タイトル）を入力してください' });
    if (!eventDate?.trim()) return res.status(400).json({ error: '開催日時（文章生成用）の日付を入力してください' });

    const OpenAI = (await import('openai')).default;
    const openai = new OpenAI({ apiKey: key });
    const isEvent = type !== 'student';

    let dateStr;
    if (eventDate) {
      const d = new Date(eventDate + 'T00:00:00');
      const dow = ['日','月','火','水','木','金','土'][d.getDay()];
      const tStart = eventTime || '10:00';
      const tEnd   = eventEndTime || '12:00';
      dateStr = `${d.getFullYear()}年${d.getMonth()+1}月${d.getDate()}日（${dow}） ${tStart}〜${tEnd}`;
    } else {
      const today = new Date();
      const dow = ['日','月','火','水','木','金','土'][today.getDay()];
      dateStr = `${today.getFullYear()}年${today.getMonth()+1}月${today.getDate()}日（${dow}） 10:00〜12:00`;
    }

    const systemPrompt = isEvent
      ? `あなたはイベント告知文の作成プロです。タイトルに沿って、魅力的で読みやすいイベント告知文を生成してください。構成: 開催日時、開催形式、参加費、内容、得られること、参加スタイル、注意事項など。プレーンテキストで、改行を適切に使い、見出しは■で区切ってください。【重要】開催日時は必ず「${dateStr}」をそのまま使用してください。それ以外の日付・時刻を記載しないでください。`
      : 'あなたは受講生サポートのメッセージ作成プロです。タイトルに沿って、受講生に寄り添う温かみのあるサポートメッセージを生成してください。押し付けがましくなく、励ましや次のステップを示す内容にしてください。';

    const userPrompt = isEvent
      ? `【開催日時】${dateStr}\n\n上記の開催日時を文章中に必ず記載してください。日付・時刻を変えないでください。\n\nタイトル：${title}`
      : `以下のタイトルに沿った文章を生成してください：\n\n${title}`;
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      temperature: 0.3,
    });
    const result = completion.choices[0]?.message?.content?.trim() || '';
    res.json({ content: result });
  } catch (err) {
    res.status(500).json({ error: err.message || '生成に失敗しました' });
  }
});

app.post('/api/ai/align-datetime', async (req, res) => {
  try {
    const { text, eventDate, eventTime, eventEndTime, apiKey } = req.body;
    const key = apiKey || process.env.OPENAI_API_KEY;
    if (!key) return res.status(400).json({ error: 'OpenAI APIキーを入力してください' });
    if (!text?.trim() || !eventDate) return res.json({ content: text });

    const d = new Date(eventDate + 'T00:00:00');
    const dow = ['日','月','火','水','木','金','土'][d.getDay()];
    const tStart = eventTime || '10:00';
    const tEnd   = eventEndTime || '12:00';
    const dateStr = `${d.getFullYear()}年${d.getMonth()+1}月${d.getDate()}日（${dow}） ${tStart}〜${tEnd}`;

    const OpenAI = (await import('openai')).default;
    const openai = new OpenAI({ apiKey: key });
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: 'あなたはテキスト編集のアシスタントです。文章中に記載されている開催日時・日付・時刻の部分のみを、指定された日時に差し替えてください。文章の他の部分は一切変更しないでください。修正後のテキスト全体のみを返してください。' },
        { role: 'user', content: `開催日時を「${dateStr}」に合わせてください。\n\n${text}` },
      ],
      temperature: 0.1,
    });
    const result = completion.choices[0]?.message?.content?.trim() || text;
    res.json({ content: result });
  } catch (err) {
    res.status(500).json({ error: err.message || '日時調整に失敗しました' });
  }
});

app.post('/api/ai/agent', async (req, res) => {
  try {
    const { text, prompt, apiKey } = req.body;
    const key = apiKey || process.env.OPENAI_API_KEY;
    if (!key) return res.status(400).json({ error: 'OpenAI APIキーを入力してください' });
    if (!prompt?.trim()) return res.status(400).json({ error: '指示を入力してください' });

    const OpenAI = (await import('openai')).default;
    const openai = new OpenAI({ apiKey: key });
    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: 'あなたは文章作成のアシスタントです。ユーザーの現在のテキストに対して、ユーザーの指示に従って修正・改善した結果を返してください。結果のテキストのみを返し、余分な説明は不要です。' },
        { role: 'user', content: `【現在のテキスト】\n${text || '(空)'}\n\n【指示】\n${prompt}` },
      ],
      temperature: 0.5,
    });
    const result = completion.choices[0]?.message?.content?.trim() || '';
    res.json({ result });
  } catch (err) {
    res.status(500).json({ error: err.message || '処理に失敗しました' });
  }
});

if (!process.env.VERCEL) {
  app.listen(3000, () => console.log('✅ サーバー起動: http://localhost:3000'));
}
export default app;
