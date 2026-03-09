/** connpass 専用（ブラウザ内 fetch API でイベント作成・更新） */

import { loginWithPlaywright } from './utils.js';

export const SITE_NAME = 'connpass';

export const config = {
  loginUrl:  process.env.CONPASS_LOGIN_URL  || 'https://connpass.com/login/',
  mypage:    process.env.CONPASS_URL        || 'https://connpass.com/',
  get email()    { return process.env.CONPASS__KOKUCIZE_MAIL; },
  get password() { return process.env.CONPASS_KOKUCIZE_PASSWORD; },
};

async function ensureLogin(page, log) {
  const cfg = {
    ...config,
    mypage:    'https://connpass.com/editmanage/',  // 要認証ページ → 未ログイン時はloginにリダイレクト
    emailSel:  'input[name="username"],input[name="email"]',
    passSel:   'input[name="password"]',
    submitSel: 'form:has(input[name="username"]) button[type="submit"]',  // ログインフォームのsubmitのみ
  };
  await loginWithPlaywright(page, cfg, SITE_NAME, log);

  await page.goto('https://connpass.com/editmanage/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  const { csrftoken, cookieNames, currentUrl } = await page.evaluate(() => {
    const cookies = document.cookie.split(';').map(c => c.trim().split('=')[0]);
    const csrf = document.cookie.split(';').find(c => c.trim().startsWith('connpass-csrftoken='));
    return {
      csrftoken: csrf ? csrf.split('=')[1].trim() : null,
      cookieNames: cookies.filter(Boolean),
      currentUrl: location.href,
    };
  });
  if (!csrftoken) throw new Error('CSRFトークンが取得できませんでした');
  log(`[connpass] 現在URL: ${currentUrl}`);
  log(`[connpass] cookie: ${cookieNames.join(', ') || '(なし)'}`);
  log(`[connpass] csrftoken: ${csrftoken.slice(0, 8)}...`);
  return csrftoken;
}

export async function post(page, content, eventFields = {}, log) {
  const csrftoken = await ensureLogin(page, log);
  const title = (eventFields.title || content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '')).slice(0, 80) || 'イベント';

  const ef = eventFields;
  const place = ef.place || 'オンライン';
  const cap = parseInt(ef.capacity, 10) || 50;
  const in30 = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const defaultYmd = in30.toISOString().slice(0, 10);
  const fmtDt = (d, t) => {
    const date = (d ? String(d).replace(/\//g, '-').slice(0, 10) : defaultYmd);
    const time = (t || '10:00').replace(/^(\d{1,2}):(\d{2})/, (_, h, m) => `${String(h).padStart(2, '0')}:${m}:00`);
    return `${date}T${time}`;
  };
  const startDatetime = fmtDt(ef.startDate, ef.startTime);
  const endDatetime = fmtDt(ef.endDate || ef.startDate, ef.endTime);
  const defaultStart = ef.startDate || defaultYmd;
  const startMs = new Date(String(defaultStart).replace(/\//g, '-')).getTime();
  const fmtIso = (date) => {
    const d = new Date(date);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}T00:00:00`;
  };
  const openStart = fmtIso(startMs - 7 * 24 * 60 * 60 * 1000);
  const openEnd = fmtIso(startMs - 1 * 24 * 60 * 60 * 1000);

  const postBody = { title, allow_conflict_join: 'true', place: null };  // placeはIDかnull
  log(`[connpass] POST /api/event/ body: ${JSON.stringify(postBody)}`);
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

  if (!createResult.ok) {
    log(`[connpass] ❌ POST失敗 status=${createResult.status} body=${createResult.text}`);
    throw new Error(`イベント作成失敗: ${createResult.status} ${createResult.text}`);
  }
  const created = JSON.parse(createResult.text);
  const eventId = created.id;
  log(`[connpass] ✅ イベント作成 ID: ${eventId}`);

  // 本文の先頭行がタイトルと同じ内容（# 見出しや【】など）なら除去
  const lines = content.split('\n');
  const firstLine = lines[0].replace(/^[#\s「『【]+/, '').replace(/[】』」\s]+$/, '').trim();
  const body = firstLine && title.includes(firstLine)
    ? lines.slice(1).join('\n').replace(/^\n+/, '')
    : content;

  const putBody = {
    ...created,
    description_input: body,
    description: body,
    status: 'draft',
    place: null,  // placeはnull（会場名は description に含める）
    start_datetime: startDatetime,
    end_datetime: endDatetime,
    open_start_datetime: openStart,
    open_end_datetime: openEnd,
  };
  if (Array.isArray(putBody.participation_types) && putBody.participation_types[0]) {
    putBody.participation_types[0].max_participants = cap;
  }

  log(`[connpass] PUT /api/event/${eventId} 本文・日時・会場更新中...`);
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
  }, { eventId, csrftoken, body: putBody });

  if (!putResult.ok) {
    log(`[connpass] ❌ PUT失敗 status=${putResult.status} body=${putResult.text}`);
    throw new Error(`本文更新失敗: ${putResult.status} ${putResult.text}`);
  }
  const updated = JSON.parse(putResult.text);
  log(`[connpass] ✅ 投稿完了 → ${updated.public_url}`);
}
