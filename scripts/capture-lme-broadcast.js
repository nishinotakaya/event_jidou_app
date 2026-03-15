/**
 * LME 下書き保存API捕捉スクリプト（最終ステップ）
 * broadcast_id=1379251 の編集ページから「下書きとして保存」をクリックする
 *
 * 実行: node scripts/capture-lme-broadcast.js
 */

import { chromium } from 'playwright';
import dotenv from 'dotenv';
import { writeFileSync } from 'fs';
dotenv.config();

const BASE_URL    = (process.env.LME_BASE_URL  || 'https://step.lme.jp').replace(/"+/g, '');
const BOT_ID      = process.env.LME_BOT_ID     || '17106';
const EMAIL       = process.env.LME_EMAIL;
const PASSWORD    = process.env.LME_PASSWORD;
const CAPTCHA_KEY = process.env.API2CAPTCHA_KEY;

const apiCalls = [];
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function solve2captcha(sitekey, pageUrl) {
  console.log('[2captcha] 送信中...');
  const r = await fetch('http://2captcha.com/in.php', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ key: CAPTCHA_KEY, method: 'userrecaptcha', googlekey: sitekey, pageurl: pageUrl, json: '1' }),
  });
  const j = await r.json();
  if (j.status !== 1) throw new Error(`2captcha 失敗: ${JSON.stringify(j)}`);
  console.log(`[2captcha] id=${j.request} 待機 (20s)...`);
  await sleep(20000);
  for (let i = 0; i < 24; i++) {
    const res = await (await fetch(`http://2captcha.com/res.php?key=${CAPTCHA_KEY}&action=get&id=${j.request}&json=1`)).json();
    if (res.status === 1) { console.log('[2captcha] ✅ 解決'); return res.request; }
    if (res.request !== 'CAPCHA_NOT_READY') throw new Error(`2captcha エラー: ${JSON.stringify(res)}`);
    process.stdout.write('.');
    await sleep(5000);
  }
  throw new Error('2captcha タイムアウト');
}

async function doLogin(page) {
  await page.goto(`${BASE_URL}/`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(1500);
  const emailEl = await page.$('#email_login, input[name="email"]');
  if (!emailEl) { console.log('[LOGIN] スキップ'); return; }
  await emailEl.fill(EMAIL);
  await (await page.$('#password_login, input[name="password"]')).fill(PASSWORD);
  const captchaEl = await page.$('.g-recaptcha');
  if (captchaEl) {
    const sitekey = await captchaEl.getAttribute('data-sitekey') || process.env.RECAPTCHA_SITE_KEY;
    const tok = await solve2captcha(sitekey, page.url());
    await page.evaluate((tok) => {
      let el = document.querySelector('#g-recaptcha-response');
      if (!el) { el = document.createElement('textarea'); el.id='g-recaptcha-response'; el.name='g-recaptcha-response'; el.style.display='none'; document.body.appendChild(el); }
      el.value = tok; el.dispatchEvent(new Event('change', { bubbles: true }));
    }, tok);
  }
  await Promise.all([page.waitForNavigation({ timeout: 35000 }).catch(() => {}), page.click('button[type="submit"]')]);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  console.log(`[LOGIN] ✅ → ${page.url()}`);
}

async function chooseAccount(page) {
  await page.goto(`${BASE_URL}/admin/home`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(2000);
  const loaEls = await page.$$(`xpath=//*[contains(normalize-space(text()), 'プロアカ')]`);
  if (loaEls.length > 0) { await loaEls[0].click().catch(() => {}); await sleep(2000); }
  console.log(`[ACCOUNT] ✅ → ${page.url()}`);
}

async function captureDraftSave(page) {
  // 前回作成した broadcast_id=1379251 の編集ページへ直接アクセス
  const editUrl = `${BASE_URL}/basic/add-broadcast-v2?broadcast_id=1379251&botIdCurrent=${BOT_ID}&isOtherBot=1`;
  console.log(`\n[DRAFT] 編集ページへ: ${editUrl}`);
  await page.goto(editUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(3000);
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  console.log(`[DRAFT] URL: ${page.url()}`);
  await page.screenshot({ path: '/tmp/lme-draft-edit.png', fullPage: true });

  // 入力フィールドにメッセージを入力
  const msgArea = await page.$('textarea[placeholder*="テキスト"], textarea[placeholder*="メッセージ"], [contenteditable="true"]');
  if (msgArea && await msgArea.isVisible()) {
    await msgArea.fill('テストメッセージ本文：自動化テスト用の下書きメッセージです。');
    console.log('[DRAFT] メッセージ本文入力完了');
  }
  await sleep(500);

  // 「下書きとして保存」ボタンをクリック
  console.log('[DRAFT] 「下書きとして保存」ボタン探索・クリック');
  const draftBtn = page.locator('button, a').filter({ hasText: '下書きとして保存' }).first();
  const cnt = await draftBtn.count();
  console.log(`[DRAFT] count: ${cnt}`);

  if (cnt > 0) {
    const box = await draftBtn.boundingBox().catch(() => null);
    console.log(`[DRAFT] bbox: ${JSON.stringify(box)}`);
    await draftBtn.click({ force: true, timeout: 10000 });
    console.log('[DRAFT] ✅ クリック完了');
    await sleep(3000);
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    console.log(`[DRAFT] 保存後 URL: ${page.url()}`);
    await page.screenshot({ path: '/tmp/lme-draft-saved.png', fullPage: true });
  } else {
    console.log('[DRAFT] ボタンが見つかりません。全ボタン:');
    const all = await page.evaluate(() =>
      [...document.querySelectorAll('button, a')].map(el => ({
        text: el.textContent.trim().slice(0,40), id: el.id, class: el.className?.slice(0,60)
      })).filter(b => b.text)
    );
    all.forEach(b => console.log(`  "${b.text}"`));
  }

  await sleep(5000);
}

(async () => {
  const browser = await chromium.launch({ headless: false, slowMo: 100 });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const page    = await context.newPage();

  page.on('request', req => {
    if (!['xhr', 'fetch'].includes(req.resourceType())) return;
    if (!req.url().includes('step.lme.jp')) return;
    const entry = { method: req.method(), url: req.url(), postData: req.postData() || null };
    apiCalls.push(entry);
    console.log(`[API ➜] ${req.method()} ${req.url()}`);
    if (req.postData()) console.log(`        ${req.postData().slice(0, 600)}`);
  });
  page.on('response', async res => {
    if (!['xhr', 'fetch'].includes(res.request().resourceType())) return;
    if (!res.url().includes('step.lme.jp')) return;
    let body = null; try { body = await res.text(); } catch {}
    const last = apiCalls.findLast(c => c.url === res.url() && !c.responseStatus);
    if (last) { last.responseStatus = res.status(); last.responseBody = body?.slice(0, 2000); }
    console.log(`[API ←] ${res.status()} ${res.url()}`);
    if (body) console.log(`        ${body.slice(0, 600)}`);
  });

  try {
    await doLogin(page);
    await chooseAccount(page);
    await captureDraftSave(page);
  } catch (e) {
    console.error('\n[ERROR]', e.message);
    await page.screenshot({ path: '/tmp/lme-error.png', fullPage: true }).catch(() => {});
  } finally {
    writeFileSync('/tmp/lme-network-dump.json', JSON.stringify({ apiCalls }, null, 2), 'utf-8');
    console.log(`\n✅ APIダンプ: /tmp/lme-network-dump.json (${apiCalls.length} calls)`);
    await sleep(3000);
    await browser.close();
  }
})();
