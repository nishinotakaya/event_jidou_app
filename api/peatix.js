/** Peatix 専用（Bearer トークンを使ったAPI投稿） */

export const SITE_NAME = 'Peatix';

// PEATIX_CREATE_URL から groupId を取得
const GROUP_ID = (() => {
  const url = process.env.PEATIX_CREATE_URL || 'https://peatix.com/group/16510066/event/create';
  const m = url.match(/group\/(\d+)/);
  return m ? m[1] : '16510066';
})();

/** Peatix 2ステップログイン + Bearer token 取得 */
async function loginAndGetBearer(page, log) {
  log(`[Peatix] ログイン中...`);
  await page.goto('https://peatix.com/signin', { waitUntil: 'domcontentloaded', timeout: 30000 });

  // すでにログイン済み（signinページにいない）ならスキップ
  if (!page.url().includes('signin') && !page.url().includes('login')) {
    log(`[Peatix] ✅ ログイン済み → ${page.url()}`);
  } else {
    // Step1: メールアドレス入力 → 次に進む
    await page.fill('input[name="username"]', process.env.PEATIX_EMAIL);
    await Promise.all([
      page.waitForURL('**/user/signin', { timeout: 15000 }),
      page.click('#next-button'),
    ]);

    // Step2: パスワード入力 → ログイン
    await page.waitForSelector('input[type="password"]', { timeout: 10000 });
    await page.fill('input[type="password"]', process.env.PEATIX_PASSWORD);
    await Promise.all([
      page.waitForNavigation({ timeout: 20000 }).catch(() => {}),
      page.click('#signin-button'),
    ]);

    const afterUrl = page.url();
    if (afterUrl.includes('signin') || afterUrl.includes('login')) {
      throw new Error('Peatix ログインに失敗しました（メール/パスワードを確認してください）');
    }
    log(`[Peatix] ✅ ログイン完了 → ${afterUrl}`);
  }

  // イベント作成ページへ移動してBearer tokenを取得
  const createUrl = process.env.PEATIX_CREATE_URL || `https://peatix.com/group/${GROUP_ID}/event/create`;
  await page.goto(createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000); // SPA描画待ち
  await page.waitForTimeout(2000);

  const token = await page.evaluate(() => localStorage.getItem('peatix_frontend_access_token'));
  if (!token) throw new Error('Bearer トークンが取得できませんでした（localStorage に peatix_frontend_access_token が見つかりません）');
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
  const bearer = await loginAndGetBearer(page, log);

  const ef = eventFields;
  const title = (ef.title || content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '')).slice(0, 100) || 'イベント';

  // content の先頭行がタイトルと同じ場合は除去
  const lines = content.split('\n');
  const firstLine = lines[0].replace(/^[#\s「『【]+/, '').replace(/[】』」\s]+$/, '').trim();
  const bodyText = firstLine && title.includes(firstLine)
    ? lines.slice(1).join('\n').replace(/^\n+/, '')
    : content;

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
        'referer': `https://peatix.com/group/${groupId}/event/create`,
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
        body: JSON.stringify({ details: { description } }),
      });
      return { ok: res.ok, status: res.status, text: await res.text() };
    }, { eventId, bearer, description: bodyText });

    if (patchResult.ok) {
      log(`[Peatix] ✅ 説明文更新完了`);
    } else {
      log(`[Peatix] ⚠️ 説明文更新失敗 (${patchResult.status}): ${patchResult.text.slice(0, 200)}`);
    }
  }

  // ===== Step3: 画像アップロード =====
  if (eventFields.imagePath && eventId) {
    log(`[Peatix] 📸 画像アップロード中...`);
    try {
      await page.goto(`https://peatix.com/event/${eventId}/edit`, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      const fileInput = page.locator('input[type="file"]').first();
      const visible = await fileInput.isVisible({ timeout: 5000 }).catch(() => false);
      if (visible) {
        await fileInput.setInputFiles(eventFields.imagePath);
        await page.waitForTimeout(2000);
        const saveBtn = page.locator('button[type="submit"]').first();
        if (await saveBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
          await saveBtn.click();
          await page.waitForTimeout(2000);
        }
        log(`[Peatix] ✅ 画像アップロード完了`);
      } else {
        log(`[Peatix] ⚠️ 画像アップロードフィールドが見つかりません`);
      }
    } catch (e) {
      log(`[Peatix] ⚠️ 画像アップロード失敗: ${e.message}`);
    }
  }

  const eventUrl = created.details?.longUrl || `https://peatix.com/event/${eventId}`;
  log(`[Peatix] ✅ 投稿完了 → ${eventUrl}`);
}
