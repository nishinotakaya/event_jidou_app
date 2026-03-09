/** Peatix 専用（Bearer トークンを使ったAPI投稿） */

import { loginWithPlaywright } from './utils.js';

export const SITE_NAME = 'Peatix';

// PEATIX_CREATE_URL から groupId を取得
const GROUP_ID = (() => {
  const url = process.env.PEATIX_CREATE_URL || 'https://peatix.com/group/16510066/event/create';
  const m = url.match(/group\/(\d+)/);
  return m ? m[1] : '16510066';
})();

export const config = {
  loginUrl:  process.env.PEATIX_LOGIN_URL || 'https://peatix.com/signin',
  mypage:    'https://peatix.com/account/edit',  // 要認証ページ → 未ログイン時はsigninにリダイレクト
  get email()    { return process.env.PEATIX_EMAIL; },
  get password() { return process.env.PEATIX_PASSWORD; },
  emailSel:  'input[name="email"]',
  passSel:   'input[name="password"]',
};

/** Bearer トークンを取得（リクエスト傍受 → localStorage フォールバック） */
async function getBearer(page, log) {
  let token = null;

  const onRequest = req => {
    const auth = req.headers()['authorization'];
    if (auth?.startsWith('Bearer ') && req.url().includes('peatix-api.com')) {
      token = auth.slice(7).trim();
    }
  };
  page.on('request', onRequest);

  // イベント作成ページ（React SPA）はAPIコールを発生させる
  const createUrl = process.env.PEATIX_CREATE_URL || `https://peatix.com/group/${GROUP_ID}/event/create`;
  await page.goto(createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(4000);
  page.off('request', onRequest);

  // リクエスト傍受で取れなければ localStorage を確認
  if (!token) {
    token = await page.evaluate(() => {
      for (const key of Object.keys(localStorage)) {
        try {
          const raw = localStorage.getItem(key) || '';
          // 直接トークン文字列
          if (/^[A-Za-z0-9_\-]{20,60}$/.test(raw)) return raw;
          // JSON形式
          const obj = JSON.parse(raw);
          if (obj?.token && typeof obj.token === 'string') return obj.token;
          if (obj?.access_token && typeof obj.access_token === 'string') return obj.access_token;
          if (obj?.accessToken && typeof obj.accessToken === 'string') return obj.accessToken;
        } catch {}
      }
      return null;
    });
    if (token) log(`[Peatix] Bearer取得(localStorage): ${token.slice(0, 8)}...`);
  }

  if (!token) throw new Error('Bearer トークンが取得できませんでした（Peatixへのログインを確認してください）');
  log(`[Peatix] Bearer取得: ${token.slice(0, 8)}...`);
  return token;
}

/** JST の日時文字列を UTC ISO 文字列に変換 */
function toUtc(dateStr, timeStr) {
  const d = String(dateStr || '').replace(/\//g, '-')
    || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const t = (timeStr || '10:00').replace(/^(\d):/, '0$1:');
  return new Date(`${d}T${t}:00+09:00`).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export async function post(page, content, eventFields = {}, log) {
  await loginWithPlaywright(page, config, SITE_NAME, log);
  const bearer = await getBearer(page, log);

  const ef = eventFields;
  const title = (ef.title || content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '')).slice(0, 100) || 'イベント';

  const startUtc = toUtc(ef.startDate, ef.startTime);
  const endUtc   = toUtc(ef.endDate || ef.startDate, ef.endTime || ef.startTime);

  // ===== Step1: イベント作成 =====
  const createBody = {
    name: title,
    groupId: GROUP_ID,
    locationType: 'online',
    schedulingType: 'single',
    countryId: 392,
    start: { utc: startUtc, timezone: 'Asia/Tokyo' },
    end:   { utc: endUtc,   timezone: 'Asia/Tokyo' },
  };
  log(`[Peatix] POST /v4/events: "${title}"`);

  const createResult = await page.evaluate(async ({ body, bearer, groupId }) => {
    const res = await fetch('https://peatix-api.com/v4/events', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'authorization': `Bearer ${bearer}`,
        'origin': 'https://peatix.com',
        'referer': `https://peatix.com/group/${groupId}/view`,
        'x-requested-with': 'XMLHttpRequest',
      },
      body: JSON.stringify(body),
    });
    return { ok: res.ok, status: res.status, text: await res.text() };
  }, { body: createBody, bearer, groupId: GROUP_ID });

  if (!createResult.ok) {
    throw new Error(`Peatix イベント作成失敗: ${createResult.status} ${createResult.text}`);
  }

  const created = JSON.parse(createResult.text);
  const eventId = created.id || created.eventId;
  log(`[Peatix] ✅ イベント作成 ID: ${eventId}`);

  // ===== Step2: 説明文を更新 =====
  // content の先頭行がタイトルと同じ場合は除去
  const lines = content.split('\n');
  const firstLine = lines[0].replace(/^[#\s「『【]+/, '').replace(/[】』」\s]+$/, '').trim();
  const bodyText = firstLine && title.includes(firstLine)
    ? lines.slice(1).join('\n').replace(/^\n+/, '')
    : content;

  if (eventId && bodyText) {
    log(`[Peatix] PATCH /v4/events/${eventId} 説明文更新中...`);
    const patchResult = await page.evaluate(async ({ eventId, bearer, description }) => {
      const res = await fetch(`https://peatix-api.com/v4/events/${eventId}`, {
        method: 'PATCH',
        headers: {
          'content-type': 'application/json',
          'authorization': `Bearer ${bearer}`,
          'origin': 'https://peatix.com',
          'referer': `https://peatix.com/event/${eventId}/edit`,
          'x-requested-with': 'XMLHttpRequest',
        },
        body: JSON.stringify({ description }),
      });
      return { ok: res.ok, status: res.status, text: await res.text() };
    }, { eventId, bearer, description: bodyText });

    if (patchResult.ok) {
      log(`[Peatix] ✅ 説明文更新完了`);
    } else {
      log(`[Peatix] ⚠️ 説明文更新失敗 (${patchResult.status}): ${patchResult.text.slice(0, 200)}`);
    }
  }

  const eventUrl = created.url || `https://peatix.com/event/${eventId}`;
  log(`[Peatix] ✅ 投稿完了 → ${eventUrl}`);
}
