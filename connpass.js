/** connpass 専用（ブラウザ内 fetch API でイベント作成・更新） */

import { loginWithPlaywright } from './utils.js';

export const SITE_NAME = 'connpass';

export const config = {
  loginUrl:  process.env.CONPASS_LOGIN_URL  || 'https://connpass.com/login/',
  mypage:    process.env.CONPASS_URL        || 'https://connpass.com/',
  email:     process.env.CONPASS__KOKUCIZE_MAIL,
  password:  process.env.CONPASS_KOKUCIZE_PASSWORD,
};

async function ensureLogin(page, log) {
  const cfg = {
    ...config,
    emailSel: 'input[name="username"],input[name="email"]',
    passSel:  'input[name="password"]',
  };
  await loginWithPlaywright(page, cfg, SITE_NAME, log);

  await page.goto('https://connpass.com/editmanage/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  const csrftoken = await page.evaluate(() => {
    const el = document.cookie.split(';').find(c => c.trim().startsWith('connpass-csrftoken='));
    return el ? el.split('=')[1].trim() : null;
  });
  if (!csrftoken) throw new Error('CSRFトークンが取得できませんでした');
  log(`[connpass] csrftoken: ${csrftoken.slice(0, 8)}...`);
  return csrftoken;
}

export async function post(page, content, _eventFields, log) {
  const csrftoken = await ensureLogin(page, log);
  const title = content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '').slice(0, 80) || 'イベント';

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
