/**
 * こくチーズ Step2 フォーム構造解析スクリプト
 * 使い方: node api/debug-kokuch.js
 * → 画面にブラウザが立ち上がってStep2まで進み、全フィールドをダンプします
 */

import dotenv from 'dotenv';
import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
dotenv.config();

const __dirname = dirname(fileURLToPath(import.meta.url));

const EMAIL    = process.env.CONPASS__KOKUCIZE_MAIL;
const PASSWORD = process.env.CONPASS_KOKUCIZE_PASSWORD;
const CREATE_URL = 'https://www.kokuchpro.com/regist/';

if (!EMAIL || !PASSWORD) {
  console.error('❌ .env に CONPASS__KOKUCIZE_MAIL / CONPASS_KOKUCIZE_PASSWORD が設定されていません');
  process.exit(1);
}

console.log(`📧 ログインアカウント: ${EMAIL}`);

const { chromium } = await import('playwright');

const browser = await chromium.launch({
  headless: false,   // ← 画面が見える状態で起動
  slowMo: 400,       // 操作をゆっくり表示
  ...(process.platform === 'darwin' && { channel: 'chrome' }),
});

const context = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
  locale: 'ja-JP',
  viewport: { width: 1280, height: 900 },
});
const page = await context.newPage();

// ============================
// 1. /regist/ へアクセス
// ============================
console.log('\n[1] /regist/ にアクセス中...');
await page.goto(CREATE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForTimeout(2000);
console.log(`    URL: ${page.url()}`);

// ============================
// 2. ログイン
// ============================
if (page.url().includes('login') || page.url().includes('signin')) {
  console.log('[2] ログイン中...');
  await page.fill('#LoginFormEmail', EMAIL);
  await page.fill('#LoginFormPassword', PASSWORD);
  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    page.click('#UserLoginForm button[type="submit"]'),
  ]);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  console.log(`    ログイン後URL: ${page.url()}`);

  if (page.url().includes('login') || page.url().includes('signin')) {
    console.error('❌ ログイン失敗');
    await browser.close();
    process.exit(1);
  }
  console.log('    ✅ ログイン完了');
} else {
  console.log('[2] ✅ ログイン済み');
}

// ============================
// 3. Step1: イベント種別選択
// ============================
const hasStep1 = await page.locator('input[name="data[Event][event_type]"]').first().isVisible({ timeout: 3000 }).catch(() => false);
if (hasStep1) {
  console.log('[3] Step1: イベント種別・参加費を選択してStep2へ...');
  await page.locator('input[name="data[Event][event_type]"][value="0"]').check().catch(() => {});
  await page.locator('input[name="data[Event][charge]"][value="0"]').check().catch(() => {});
  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    page.evaluate(() => {
      const f = [...document.querySelectorAll('form')].find(f => f.querySelector('input[name="data[step]"]'));
      if (f) f.submit();
    }),
  ]);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  console.log(`    Step2 URL: ${page.url()}`);
} else {
  console.log('[3] Step1なし / すでにStep2');
}

await page.waitForTimeout(2500);

// ============================
// 4. Step2 フォーム完全解析
// ============================
console.log('\n[4] Step2フォーム構造を解析中...\n');

const analysis = await page.evaluate(() => {
  const result = {
    url: window.location.href,
    title: document.title,
    jquery: !!(window.jQuery || window.$),
    jqueryVersion: (window.jQuery || window.$ || {}).fn?.jquery || null,
    tinymce: typeof tinymce !== 'undefined' ? tinymce.editors.map(e => ({ id: e.id, targetId: e.targetElm?.id })) : [],
    forms: [],
    hasDatepickerFields: [],
    allFields: [],
  };

  // hasDatepicker フィールド
  result.hasDatepickerFields = [...document.querySelectorAll('input.hasDatepicker')].map(el => ({
    id: el.id, name: el.name, value: el.value, type: el.type,
  }));

  // 全フォーム
  document.querySelectorAll('form').forEach((form, fi) => {
    const fields = [...form.querySelectorAll('input, textarea, select')]
      .filter(el => el.name)
      .map(el => ({
        tag: el.tagName,
        type: el.type || '',
        name: el.name,
        id: el.id || '',
        value: el.value?.slice(0, 50) || '',
        required: el.required,
        readonly: el.readOnly,
        disabled: el.disabled,
        visible: el.offsetParent !== null,
        classes: el.className,
      }));
    result.forms.push({
      index: fi,
      action: form.action,
      method: form.method,
      fieldCount: fields.length,
      fields,
    });
  });

  // 全フィールド（フォーム横断）
  result.allFields = [...document.querySelectorAll('input, textarea, select')]
    .filter(el => el.name)
    .map(el => ({
      tag: el.tagName,
      type: el.type || '',
      name: el.name,
      id: el.id || '',
      value: el.value?.slice(0, 50) || '',
      visible: el.offsetParent !== null,
    }));

  return result;
});

// ============================
// 5. 結果を表示
// ============================
console.log('========== 解析結果 ==========');
console.log(`URL   : ${analysis.url}`);
console.log(`jQuery: ${analysis.jquery ? `✅ v${analysis.jqueryVersion}` : '❌ 未検出'}`);
console.log(`TinyMCE: ${analysis.tinymce.length ? JSON.stringify(analysis.tinymce) : '未使用'}`);
console.log(`\n[hasDatepicker フィールド (${analysis.hasDatepickerFields.length}件)]`);
analysis.hasDatepickerFields.forEach(f => {
  console.log(`  name="${f.name}" id="${f.id}" type="${f.type}" value="${f.value}"`);
});

console.log(`\n[フォーム一覧 (${analysis.forms.length}個)]`);
analysis.forms.forEach(form => {
  console.log(`\n  Form[${form.index}] action="${form.action}" method="${form.method}" fields=${form.fieldCount}`);
  form.fields.forEach(f => {
    const vis = f.visible ? '👁' : '🙈';
    const req = f.required ? '✱' : ' ';
    console.log(`    ${vis}${req} ${f.tag}[${f.name}] type=${f.type} id="${f.id}" value="${f.value}" cls="${f.classes.slice(0,40)}"`);
  });
});

// ============================
// 6. 対象フィールドの存在確認
// ============================
const TARGET_FIELDS = [
  'data[Event][name]',
  'data[Event][description]',
  'data[EventDate][start_date_date]',
  'data[EventDate][start_date_time]',
  'data[EventDate][end_date_date]',
  'data[EventDate][end_date_time]',
  'data[EventDate][entry_start_date_date]',
  'data[EventDate][entry_end_date_date]',
  'data[EventDate][total_capacity]',
  'data[Event][place]',
  'data[Event][country]',
  'data[Event][tel]',
  'data[Event][email]',
  'data[EventPage][body_html]',
];

console.log('\n[必須フィールド存在確認]');
const fieldNames = analysis.allFields.map(f => f.name);
TARGET_FIELDS.forEach(name => {
  const found = fieldNames.includes(name);
  console.log(`  ${found ? '✅' : '❌'} ${name}`);
});

// 推定フィールド名（類似検索）
const dateRelated = analysis.allFields.filter(f =>
  f.name.toLowerCase().includes('date') || f.name.toLowerCase().includes('time') || f.name.toLowerCase().includes('entry')
);
if (dateRelated.length > 0) {
  console.log('\n[date/time/entry を含む実際のフィールド名]');
  dateRelated.forEach(f => console.log(`  ${f.tag}[${f.name}] id="${f.id}" type="${f.type}" vis=${f.visible}`));
}

// ============================
// 7. JSONファイルに保存
// ============================
const outPath = join(__dirname, 'kokuch-debug-analysis.json');
writeFileSync(outPath, JSON.stringify(analysis, null, 2), 'utf-8');
console.log(`\n✅ 解析結果を保存: ${outPath}`);
console.log('\n⏸  ブラウザを閉じるまでStep2フォームが見えます。確認してください。');
console.log('   Enterキーで終了します...');

// Enterキーで終了
process.stdin.setRawMode(true);
process.stdin.resume();
process.stdin.on('data', async () => {
  await browser.close();
  process.exit(0);
});
