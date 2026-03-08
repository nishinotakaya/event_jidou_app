import express from 'express';
import { readFile, writeFile } from 'fs/promises';
import { existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';
dotenv.config();

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

// ===== サイト設定（.envから読み込む） =====
const SITE_CONFIGS = {
  'こくチーズ': {
    loginUrl:  process.env.KOKUCH_LOGIN_URL     || 'https://www.kokuchpro.com/auth/login/',
    mypage:    process.env.CONPASS_KOKUCIZE_URL  || 'https://www.kokuchpro.com/mypage/',
    createUrl: process.env.KOKUCH_CREATE_URL    || 'https://www.kokuchpro.com/regist/',
    email:     process.env.CONPASS__KOKUCIZE_MAIL,
    password:  process.env.CONPASS_KOKUCIZE_PASSWORD,
    emailSel:  '#LoginFormEmail, input[name="data[LoginForm][email]"]',
    passSel:   '#LoginFormPassword, input[name="data[LoginForm][password]"]',
    submitSel: '#UserLoginForm button[type="submit"]',
  },
  'Peatix': {
    loginUrl:  process.env.PEATIX_LOGIN_URL  || 'https://peatix.com/signin',
    mypage:    process.env.PEATIX_URL        || 'https://peatix.com/',
    createUrl: process.env.PEATIX_CREATE_URL || 'https://peatix.com/group/16510066/event/create',
    email:     process.env.PEATIX_EMAIL,
    password:  process.env.PEATIX_PASSWORD,
    emailSel:  'input[name="email"]',
    passSel:   'input[name="password"]',
  },
  'connpass': {
    loginUrl:  process.env.CONPASS_LOGIN_URL  || 'https://connpass.com/login/',
    mypage:    process.env.CONPASS_URL        || 'https://connpass.com/',
    email:     process.env.CONPASS__KOKUCIZE_MAIL,
    password:  process.env.CONPASS_KOKUCIZE_PASSWORD,
  },
  'techplay': {
    loginUrl:  process.env.TECHPLAY_LOGIN_URL  || 'https://techplay.jp/signin',
    mypage:    process.env.TECHPLAY_URL        || 'https://techplay.jp/',
    createUrl: process.env.TECHPLAY_CREATE_URL || 'https://techplay.jp/event/create',
    email:     process.env.TECHPLAY_EMAIL,
    password:  process.env.TECHPLAY_PASSWORD,
    emailSel:  'input[name="email"]',
    passSel:   'input[name="password"]',
  },
};

// ===== ユーティリティ =====

async function findVisible(page, ...selectors) {
  for (const sel of selectors) {
    const visible = await page.locator(sel).first().isVisible({ timeout: 2000 }).catch(() => false);
    if (visible) return sel;
  }
  return null;
}

async function check404(page, site, log) {
  const title = await page.title().catch(() => '');
  const url   = page.url();
  log(`[${site}] URL: ${url} | タイトル: "${title}"`);
  if (title.includes('404') || title.includes('見つかりません') || title.includes('Not Found') || url.includes('/404')) {
    throw new Error(`ページが見つかりません (404): ${url}`);
  }
}

async function loginWithPlaywright(page, cfg, site, log) {
  log(`[${site}] ログイン確認 → ${cfg.mypage}`);
  await page.goto(cfg.mypage, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1000);

  const url = page.url();
  const needLogin = url.includes('login') || url.includes('signin') || url.includes('sign_in');
  if (!needLogin) { log(`[${site}] ✅ ログイン済み`); return; }

  log(`[${site}] ログイン中 → ${cfg.loginUrl}`);
  await page.goto(cfg.loginUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

  const emailSel = await findVisible(page, ...cfg.emailSel.split(',').map(s => s.trim()));
  if (!emailSel) throw new Error(`[${site}] メールフィールドが見つかりません`);
  await page.fill(emailSel, cfg.email);

  const passSel = await findVisible(page, ...cfg.passSel.split(',').map(s => s.trim()));
  if (!passSel) throw new Error(`[${site}] パスワードフィールドが見つかりません`);
  await page.fill(passSel, cfg.password);

  // サイト固有のsubmitSelを優先し、なければ汎用セレクタ
  const submitCandidates = [
    ...(cfg.submitSel ? cfg.submitSel.split(',').map(s => s.trim()) : []),
    'button[type="submit"]', 'input[type="submit"]',
  ];
  const submitSel = await findVisible(page, ...submitCandidates);
  if (!submitSel) throw new Error(`[${site}] ログインボタンが見つかりません`);

  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    page.click(submitSel),
  ]);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});

  // ログイン後のセッション検証
  const afterUrl = page.url();
  if (afterUrl.includes('login') || afterUrl.includes('signin') || afterUrl.includes('sign_in')) {
    throw new Error(`[${site}] ログインに失敗しました（認証情報を確認してください）`);
  }
  log(`[${site}] ✅ ログイン完了 → ${afterUrl}`);
}

async function fillAndSubmit(page, cfg, site, content, log) {
  log(`[${site}] 投稿ページへ移動 → ${cfg.createUrl}`);
  await page.goto(cfg.createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  await check404(page, site, log);

  // ページが投稿フォームかどうか確認（ログインページにリダイレクトされていないか）
  const currentUrl = page.url();
  if (currentUrl.includes('login') || currentUrl.includes('signin')) {
    throw new Error(`[${site}] 投稿ページへのアクセスに失敗しました（再ログインが必要かもしれません）`);
  }

  // フォーム構造を読み取る
  const fields = await page.evaluate(() =>
    [...document.querySelectorAll('input, textarea, select')].map(el => ({
      tag: el.tagName.toLowerCase(), type: el.type || '',
      name: el.name || '', id: el.id || '', ph: el.placeholder || '',
      required: el.required || el.getAttribute('aria-required') === 'true',
    }))
  );
  log(`[${site}] フォーム項目: ${fields.map(f => f.name || f.id || f.ph).filter(Boolean).join(', ')}`);

  // ===== 必須フィールドをデフォルト値で埋める =====
  const in30days = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const defaultDate = in30days.toISOString().slice(0, 10);
  const defaultDatetime = in30days.toISOString().slice(0, 16);

  for (const f of fields) {
    if (!f.required) continue;
    const sel = f.id ? `#${CSS.escape(f.id)}` : f.name ? `${f.tag}[name="${f.name}"]` : null;
    if (!sel) continue;
    const el = page.locator(sel).first();
    const visible = await el.isVisible({ timeout: 1000 }).catch(() => false);
    if (!visible) continue;
    const current = await el.inputValue().catch(() => '');
    if (current) continue; // すでに値があればスキップ

    if (f.tag === 'select') {
      await page.evaluate((s) => {
        const el = document.querySelector(s);
        const opt = el && [...el.options].find(o => o.value && o.value !== '0' && o.value !== '');
        if (opt) el.value = opt.value;
      }, sel).catch(() => {});
      log(`[${site}] 必須select入力: ${f.name || f.id}`);
    } else if (f.type === 'datetime-local') {
      await el.fill(defaultDatetime).catch(() => {});
      log(`[${site}] 必須日時入力: ${f.name || f.id} = ${defaultDatetime}`);
    } else if (f.type === 'date') {
      await el.fill(defaultDate).catch(() => {});
      log(`[${site}] 必須日付入力: ${f.name || f.id} = ${defaultDate}`);
    } else if (f.type === 'time') {
      await el.fill('10:00').catch(() => {});
      log(`[${site}] 必須時刻入力: ${f.name || f.id} = 10:00`);
    } else if (f.type === 'number') {
      await el.fill('50').catch(() => {});
      log(`[${site}] 必須数値入力: ${f.name || f.id} = 50`);
    } else if (f.type === 'text' || f.type === '') {
      const n = (f.name + f.id + f.ph).toLowerCase();
      let val = '要確認';
      if (n.includes('place') || n.includes('venue') || n.includes('会場') || n.includes('場所')) val = 'オンライン';
      else if (n.includes('url') || n.includes('link')) val = 'https://example.com';
      else if (n.includes('email') || n.includes('mail')) val = cfg.email || 'info@example.com';
      else if (n.includes('tel') || n.includes('phone')) val = '000-0000-0000';
      await el.fill(val).catch(() => {});
      log(`[${site}] 必須テキスト入力: ${f.name || f.id} = "${val}"`);
    }
  }

  // 本文フィールドを動的検出
  const textareaSelectors = fields
    .filter(f => f.tag === 'textarea')
    .map(f => f.name ? `textarea[name="${f.name}"]` : f.id ? `textarea[id="${f.id}"]` : null)
    .filter(Boolean);

  const contentSel = await findVisible(page, ...textareaSelectors, 'div[contenteditable="true"]', 'textarea');
  if (!contentSel) throw new Error(`[${site}] 本文フィールドが見つかりません`);
  log(`[${site}] 本文フィールド: ${contentSel}`);
  await page.fill(contentSel, content);

  // タイトルフィールドを動的検出
  const titleSel = await findVisible(page, 'input[name="title"]', 'input[id="title"]', 'input[name="name"]', 'input[id="name"]');
  if (titleSel) {
    const current = await page.inputValue(titleSel).catch(() => '');
    if (!current) {
      const titleText = content.split('\n')[0].replace(/^[#【\s]+/, '').replace(/】$/, '').slice(0, 80);
      await page.fill(titleSel, titleText);
      log(`[${site}] タイトル入力: "${titleText}"`);
    }
  }

  // 送信ボタン
  const submitSel = await findVisible(page,
    'button[type="submit"]', 'input[type="submit"]',
    'button:has-text("投稿")', 'button:has-text("保存")', 'button:has-text("公開")',
    'button:has-text("Submit")', 'button:has-text("Save")', 'button:has-text("Publish")',
  );
  if (!submitSel) throw new Error(`[${site}] 送信ボタンが見つかりません`);
  log(`[${site}] 送信: ${submitSel}`);

  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    page.click(submitSel),
  ]);
  await check404(page, site, log);
  log(`[${site}] ✅ 投稿完了 → ${page.url()}`);
}

// ===== こくチーズ専用ハンドラー（TinyMCE + 多段フォーム対応） =====
async function kokuchPost(page, content, log) {
  const cfg = SITE_CONFIGS['こくチーズ'];
  const title = content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '').slice(0, 80) || 'イベント';

  // 1. /regist/ へ直接アクセス（ログインリダイレクトをその場で処理）
  log(`[こくチーズ] /regist/ にアクセス中...`);
  await page.goto(cfg.createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);

  // 2. ログインページにリダイレクトされていたら認証
  if (page.url().includes('login') || page.url().includes('signin')) {
    log(`[こくチーズ] ログイン中...`);
    await page.fill('#LoginFormEmail', cfg.email);
    await page.fill('#LoginFormPassword', cfg.password);
    await Promise.all([
      page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
      page.click('#UserLoginForm button[type="submit"]'),
    ]);
    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
    if (page.url().includes('login') || page.url().includes('signin')) {
      throw new Error('ログインに失敗しました（認証情報を確認してください）');
    }
    log(`[こくチーズ] ✅ ログイン完了 → ${page.url()}`);
  } else {
    log(`[こくチーズ] ✅ ログイン済み`);
  }

  // 3. Step 1: ラジオボタン（event_type / charge）を選択して次へ
  const hasStep1 = await page.locator('input[name="data[Event][event_type]"]').first().isVisible({ timeout: 2000 }).catch(() => false);
  if (hasStep1) {
    log(`[こくチーズ] Step1: イベント種別・参加費選択`);
    await page.locator('input[name="data[Event][event_type]"][value="0"]').check().catch(() => {});
    await page.locator('input[name="data[Event][charge]"][value="0"]').check().catch(() => {}); // 無料

    // navbar の検索ボタンを避けるため、data[step] を持つメインフォームを直接submit
    await Promise.all([
      page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
      page.evaluate(() => {
        const mainForm = [...document.querySelectorAll('form')].find(f =>
          f.querySelector('input[name="data[step]"]')
        );
        if (mainForm) mainForm.submit();
      }),
    ]);
    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
    log(`[こくチーズ] Step2へ → ${page.url()}`);
  }

  // 4. タイトル入力（data[Event][title] または汎用）
  const titleSel = await findVisible(page,
    'input[name="data[Event][title]"]', '#EventTitle',
    'input[name*="title"]', 'input[id*="itle"]',
  );
  if (titleSel) {
    await page.fill(titleSel, title);
    log(`[こくチーズ] タイトル入力: "${title}"`);
  }

  // 5. TinyMCE で本文入力（隠しtextareaのsyncも実行）
  await page.waitForTimeout(2000); // TinyMCE初期化待ち
  const tinyIds = await page.evaluate((html) => {
    if (typeof tinymce === 'undefined' || !tinymce.editors || tinymce.editors.length === 0) return null;
    tinymce.editors.forEach(ed => {
      ed.setContent(html.replace(/\n/g, '<br>'));
      ed.save(); // 裏のtextareaにsync
    });
    return tinymce.editors.map(ed => ed.id);
  }, content).catch(() => null);

  if (tinyIds) {
    log(`[こくチーズ] TinyMCE入力完了: [${tinyIds.join(', ')}]`);
  } else {
    // フォールバック: 表示されているtextarea / contenteditable
    const ta = await findVisible(page,
      'textarea[name*="body"]', 'textarea[name*="detail"]',
      'textarea[name*="content"]', 'textarea[name*="description"]',
      'div[contenteditable="true"]', 'textarea',
    );
    if (!ta) throw new Error('本文フィールドが見つかりません（TinyMCEもtextareaもなし）');
    await page.fill(ta, content);
    log(`[こくチーズ] textarea入力: ${ta}`);
  }

  // 6. 送信（navbar検索フォームを避けてメインフォームを直接submit）
  const submitted = await page.evaluate(() => {
    // data[step] を持つフォーム、または navbar-form でないフォームを探す
    const mainForm = [...document.querySelectorAll('form')].find(f =>
      !f.classList.contains('navbar-form') &&
      f !== document.querySelector('.navbar-form')
    );
    if (!mainForm) return false;
    const btn = mainForm.querySelector('button[type="submit"], input[type="submit"]');
    const btnText = btn ? btn.textContent.trim() : '(不明)';
    if (btn) { btn.click(); return btnText; }
    mainForm.submit();
    return 'form.submit()';
  });
  if (!submitted) throw new Error('送信ボタンが見つかりません');
  log(`[こくチーズ] 送信: "${submitted}"`);
  await page.waitForNavigation({ timeout: 30000 }).catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  log(`[こくチーズ] ✅ 投稿完了 → ${page.url()}`);
}

// ===== connpass: page.evaluate で fetch（ブラウザ内APIコール） =====
async function postToConnpass(page, log) {
  const cfg = SITE_CONFIGS['connpass'];
  await loginWithPlaywright(page, { ...cfg, emailSel: 'input[name="username"],input[name="email"]', passSel: 'input[name="password"]' }, 'connpass', log);

  // editmanageページに移動してCSRFトークンを取得
  await page.goto('https://connpass.com/editmanage/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  const csrftoken = await page.evaluate(() => {
    const el = document.cookie.split(';').find(c => c.trim().startsWith('connpass-csrftoken='));
    return el ? el.split('=')[1].trim() : null;
  });
  if (!csrftoken) throw new Error('CSRFトークンが取得できませんでした');
  log(`[connpass] csrftoken: ${csrftoken.slice(0, 8)}...`);
  return csrftoken;
}

async function connpassPost(page, content, log) {
  const csrftoken = await postToConnpass(page, log);
  const title = content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '').slice(0, 80) || 'イベント';

  // Step1: POST /api/event/ でイベント作成（ブラウザ内fetchで実行 → cookie自動付与）
  log(`[connpass] POST /api/event/ → "${title}"`);
  const createResult = await page.evaluate(async ({ title, csrftoken }) => {
    const res = await fetch('/api/event/', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-csrftoken': csrftoken,
        'x-requested-with': 'XMLHttpRequest',
      },
      credentials: 'include',
      body: JSON.stringify({ title, allow_conflict_join: 'true', place: null }),
    });
    return { ok: res.ok, status: res.status, text: await res.text() };
  }, { title, csrftoken });

  if (!createResult.ok) throw new Error(`イベント作成失敗: ${createResult.status} ${createResult.text}`);
  const created = JSON.parse(createResult.text);
  const eventId = created.id;
  log(`[connpass] ✅ イベント作成 ID: ${eventId}`);

  // Step2: PUT /api/event/{id} で本文を更新
  log(`[connpass] PUT /api/event/${eventId} 本文更新中...`);
  const putResult = await page.evaluate(async ({ eventId, csrftoken, body }) => {
    const res = await fetch(`/api/event/${eventId}`, {
      method: 'PUT',
      headers: {
        'content-type': 'application/json',
        'x-csrftoken': csrftoken,
        'x-requested-with': 'XMLHttpRequest',
        'referer': `https://connpass.com/event/${eventId}/edit/`,
      },
      credentials: 'include',
      body: JSON.stringify(body),
    });
    return { ok: res.ok, status: res.status, text: await res.text() };
  }, { eventId, csrftoken, body: { ...created, description_input: content, description: content, status: 'draft' } });

  if (!putResult.ok) throw new Error(`本文更新失敗: ${putResult.status} ${putResult.text}`);
  const updated = JSON.parse(putResult.text);
  log(`[connpass] ✅ 投稿完了 → ${updated.public_url}`);
}

// ===== SSEで投稿実行（headless・バックグラウンド） =====
app.post('/api/post', async (req, res) => {
  const { content, sites } = req.body;

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
        if (site === 'connpass') {
          await connpassPost(page, content, log);
        } else if (site === 'こくチーズ') {
          await kokuchPost(page, content, log);
        } else {
          const cfg = SITE_CONFIGS[site];
          await loginWithPlaywright(page, cfg, site, log);
          await fillAndSubmit(page, cfg, site, content, log);
        }
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
