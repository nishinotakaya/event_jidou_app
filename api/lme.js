/** LME (step.lme.jp) ログイン・メッセージ配信下書き作成 */

export const SITE_NAME = 'LME';

// env vars are read lazily inside functions to avoid ESM import-hoisting issues with dotenv
const BASE_URL    = () => (process.env.LME_BASE_URL || 'https://step.lme.jp').replace(/"+/g, '');
const BOT_ID      = () => process.env.LME_BOT_ID || '17106';
const EMAIL       = () => process.env.LME_EMAIL;
const PASSWORD    = () => process.env.LME_PASSWORD;
const CAPTCHA_KEY = () => process.env.API2CAPTCHA_KEY;

// ===== reCAPTCHA (2captcha) =====

async function solve2captcha(sitekey, pageUrl) {
  const inRes = await fetch('http://2captcha.com/in.php', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      key:       CAPTCHA_KEY(),
      method:    'userrecaptcha',
      googlekey: sitekey,
      pageurl:   pageUrl,
      json:      '1',
    }),
  });
  const inJson = await inRes.json();
  if (inJson.status !== 1) throw new Error(`2captcha 投稿失敗: ${JSON.stringify(inJson)}`);

  const requestId = inJson.request;
  await sleep(20000); // 初回待機

  for (let i = 0; i < 24; i++) {
    const resUrl = `http://2captcha.com/res.php?key=${CAPTCHA_KEY()}&action=get&id=${requestId}&json=1`;
    const resRes = await fetch(resUrl);
    const resJson = await resRes.json();
    if (resJson.status === 1) return resJson.request;
    if (resJson.request !== 'CAPCHA_NOT_READY') throw new Error(`2captcha エラー: ${JSON.stringify(resJson)}`);
    await sleep(5000);
  }
  throw new Error('2captcha タイムアウト（2分）');
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ===== セッション判定ヘルパ =====

function isLoginPage(url, title) {
  return url.endsWith('/') || url.includes('/login') || url.includes('/signin') ||
         title.includes('ログイン') || title.toLowerCase().includes('login');
}

async function hasSessionCookie(context) {
  const cookies = await context.cookies();
  return cookies.some(c => c.name === 'laravel_session' || c.name === 'XSRF-TOKEN');
}

function buildBasicUrl(path) {
  const ts = Date.now();
  return `${BASE_URL()}${path}?botIdCurrent=${encodeURIComponent(BOT_ID())}&isOtherBot=1&_ts=${ts}`;
}

// ===== メインログイン =====

export async function login(page, log) {
  if (!EMAIL() || !PASSWORD()) throw new Error('LME_EMAIL / LME_PASSWORD が .env に未設定です');

  log(`[LME] トップページへ移動`);
  await page.goto(`${BASE_URL()}/`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});

  const title = await page.title().catch(() => '');
  const url   = page.url();
  log(`[LME] title="${title}" url=${url}`);

  // すでにログイン済みか確認
  if (!isLoginPage(url, title) && await hasSessionCookie(page.context())) {
    log(`[LME] ✅ ログイン済み → /basic へ移動`);
    await page.goto(buildBasicUrl('/basic/friendlist'), { waitUntil: 'domcontentloaded', timeout: 30000 });
    return;
  }

  // ===== メール / パスワード入力 =====
  const emailSel = await findFirst(page, '#email_login', 'input[name="email"]');
  if (!emailSel) throw new Error('[LME] メールフィールドが見つかりません');
  await page.fill(emailSel, EMAIL());

  const passSel = await findFirst(page, '#password_login', 'input[name="password"]');
  if (!passSel) throw new Error('[LME] パスワードフィールドが見つかりません');
  await page.fill(passSel, PASSWORD());

  // ===== reCAPTCHA =====
  const hasCaptcha = await page.locator('.g-recaptcha').isVisible({ timeout: 3000 }).catch(() => false);
  if (hasCaptcha) {
    log(`[LME] reCAPTCHA 検出 → 2captcha で解決中...`);
    const sitekey = await page.locator('.g-recaptcha').getAttribute('data-sitekey');
    const token   = await solve2captcha(sitekey, page.url());
    await page.evaluate((tok) => {
      let el = document.querySelector('#g-recaptcha-response');
      if (!el) {
        el = document.createElement('textarea');
        el.id   = 'g-recaptcha-response';
        el.name = 'g-recaptcha-response';
        el.style.display = 'none';
        document.body.appendChild(el);
      }
      el.value = tok;
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }, token);
    log(`[LME] ✅ reCAPTCHA 解決完了`);
  } else {
    log(`[LME] reCAPTCHA なし → スキップ`);
  }

  // ===== ログインボタンクリック =====
  log(`[LME] ログインボタンをクリック`);
  await Promise.all([
    page.waitForNavigation({ timeout: 35000 }).catch(() => {}),
    page.click('button[type="submit"]'),
  ]);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});

  // ===== ログイン確認 =====
  const afterUrl   = page.url();
  const afterTitle = await page.title().catch(() => '');
  if (isLoginPage(afterUrl, afterTitle)) {
    throw new Error(`[LME] ログイン失敗（認証情報またはreCAPTCHAを確認） url=${afterUrl}`);
  }
  if (!await hasSessionCookie(page.context())) {
    throw new Error(`[LME] セッションCookieが取得できませんでした`);
  }
  log(`[LME] ✅ ログイン完了 → ${afterUrl}`);

  // ===== /basic へ移動してセッションを確定 =====
  log(`[LME] /basic/friendlist へ移動してセッション確定`);
  await page.goto(buildBasicUrl('/basic/friendlist'), { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});

  const basicUrl = page.url();
  if (!basicUrl.includes('/basic/')) {
    // fallback: overview
    await page.goto(buildBasicUrl('/basic/overview'), { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
  }
  log(`[LME] ✅ セッション確定 → ${page.url()}`);
}

async function findFirst(page, ...selectors) {
  for (const sel of selectors) {
    const visible = await page.locator(sel).first().isVisible({ timeout: 2000 }).catch(() => false);
    if (visible) return sel;
  }
  return null;
}

// ===== アカウント選択（プロアカ） =====

async function selectAccount(page, log) {
  log(`[LME] アカウント選択（プロアカ）へ移動`);
  await page.goto(`${BASE_URL()}/admin/home`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(2000);
  const loaEls = await page.$$(`xpath=//*[contains(normalize-space(text()), 'プロアカ')]`);
  if (loaEls.length > 0) {
    await loaEls[0].click().catch(() => {});
    await sleep(2000);
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  }
  log(`[LME] アカウント選択完了 → ${page.url()}`);
}

// ===== ブラウザ内fetch（セッションcookieを使用） =====

async function lmeFetch(page, path, { method = 'POST', body, contentType } = {}) {
  return page.evaluate(async ([base, path, method, body, contentType]) => {
    const rawCookie = document.cookie.split(';').find(c => c.trim().startsWith('XSRF-TOKEN='));
    const csrfToken = rawCookie ? decodeURIComponent(rawCookie.split('=').slice(1).join('=')) : '';
    const headers = {
      'X-CSRF-TOKEN': csrfToken,
      'X-Requested-With': 'XMLHttpRequest',
    };
    if (contentType) headers['Content-Type'] = contentType;
    const res = await fetch(base + path, { method, headers, body });
    const text = await res.text();
    try { return JSON.parse(text); } catch { return { _text: text, _status: res.status }; }
  }, [BASE_URL(), path, method, body ?? null, contentType ?? null]);
}

// ===== 投稿（メッセージ配信下書き作成） =====

export async function post(page, content, eventFields = {}, log) {
  // 1. ログイン
  await login(page, log);

  // 2. アカウント選択
  await selectAccount(page, log);

  // 3. CSRF取得のためメッセージ配信ページへ移動
  await page.goto(`${BASE_URL()}/basic/message-send-all`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});

  // 4. プロファイル取得
  log(`[LME] プロファイル取得中...`);
  const profileRes = await lmeFetch(page, '/ajax/broadcast/init-list-bots-profiles', {
    body: 'profile_id=',
    contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
  });
  const profile = profileRes.data?.[0];
  if (!profile) throw new Error(`[LME] プロファイルが取得できませんでした: ${JSON.stringify(profileRes)}`);
  log(`[LME] プロファイル: id=${profile.id} name=${profile.nick_name}`);

  // 5. アクティブ友達数取得
  log(`[LME] アクティブ友達数取得中...`);
  const overviewRes = await lmeFetch(page, '/basic/static-overview', { method: 'GET' });
  const todayStr = new Date().toISOString().slice(0, 10);
  const filterNumber = overviewRes.dates?.[todayStr]?.active_friend ?? 471;
  log(`[LME] アクティブ友達数: ${filterNumber}`);

  // 6. 配信パラメータ設定
  const name = (eventFields.title || content.split('\n')[0].replace(/^[#【\s]+/, '').replace(/[】\s]+$/, '')).slice(0, 50) || 'イベントお知らせ';
  const sendDay  = eventFields.startDate || todayStr;
  const sendTime = eventFields.startTime || '10:00';

  // 7. 新規broadcast作成（下書き）
  log(`[LME] 下書き配信を作成中... name="${name}"`);
  const broadcastBody = new URLSearchParams({
    broadcast_id: '',
    type: '',
    send_day: sendDay,
    send_time: sendTime,
    setting_send_message: '1',
    profile_id: String(profile.id),
    filter_number: String(filterNumber),
    filter_date: '',
    name,
    action_id: '',
    'profile_bot[id]':         String(profile.id),
    'profile_bot[bot_id]':     String(profile.bot_id),
    'profile_bot[user_id]':    String(profile.user_id),
    'profile_bot[avt_path]':   profile.avt_path,
    'profile_bot[nick_name]':  profile.nick_name,
    'profile_bot[is_default]': String(profile.is_default),
    'profile_bot[created_at]': profile.created_at,
    'profile_bot[updated_at]': profile.updated_at,
    'profile_bot[position]':   String(profile.position),
    checkFilter:         '1',
    flag_setting_filter: '0',
    count_filter:        String(filterNumber),
    status:              'draft',
  }).toString();

  const broadcastRes = await lmeFetch(page, '/ajax/save-broadcast-v2', {
    body: broadcastBody,
    contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
  });
  log(`[LME] save-broadcast-v2: ${JSON.stringify(broadcastRes)}`);

  const broadcastId = broadcastRes.broadcastIdNew ?? broadcastRes.broadcast_id ?? broadcastRes.data?.id ?? broadcastRes.id;
  if (!broadcastId) throw new Error(`[LME] broadcast_id が取得できませんでした: ${JSON.stringify(broadcastRes)}`);
  log(`[LME] broadcast_id=${broadcastId}`);

  // 8. メッセージ本文テンプレートを保存
  log(`[LME] メッセージ本文を保存中...`);
  const templateJson = JSON.stringify({
    type: 'text',
    message_button: {},
    message_media: {},
    message_stamp: {},
    message_location: {},
    message_text: {
      content,
      urls: [],
      number_action_url_redirect: 1,
      use_preview_url: 1,
      is_shorten_url: 1,
    },
    message_introduction: {},
    template_group_id: '-11',
    template_child_id: '',
    tmp_name: '',
    action_type: 'sendAll',
    broadcastId: String(broadcastId),
    scheduleSendId: '',
    conversationId: '',
    content: '',
    address: '',
    latitude: '',
    longitude: '',
  });

  const base = BASE_URL();
  const templateRes = await page.evaluate(async ([base, broadcastId, templateJson]) => {
    const rawCookie = document.cookie.split(';').find(c => c.trim().startsWith('XSRF-TOKEN='));
    const csrfToken = rawCookie ? decodeURIComponent(rawCookie.split('=').slice(1).join('=')) : '';

    const fd = new FormData();
    fd.append('data', templateJson);
    fd.append('file_media', new Blob([]));
    fd.append('thumbnail_media', new Blob([]));
    fd.append('action_type', 'sendAll');
    fd.append('templateName', '');
    fd.append('folderId', '0');

    const res = await fetch(`${base}/ajax/template-v2/save-template`, {
      method: 'POST',
      headers: {
        'X-CSRF-TOKEN': csrfToken,
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': `${base}/basic/template-v2/add-template?template_group_id=-11&action_type=sendAll&broadcastId=${broadcastId}`,
        'X-Server': 'data',
      },
      body: fd,
    });
    const text = await res.text();
    try { return JSON.parse(text); } catch { return { _text: text, _status: res.status }; }
  }, [base, broadcastId, templateJson]);

  log(`[LME] save-template: ${JSON.stringify(templateRes)}`);

  if (templateRes.status === false || templateRes.success === false) {
    throw new Error(`[LME] テンプレート保存失敗: ${JSON.stringify(templateRes)}`);
  }

  log(`[LME] ✅ 下書き作成完了 broadcast_id=${broadcastId} → ${base}/basic/add-broadcast-v2?broadcast_id=${broadcastId}`);
}
