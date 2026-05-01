/**
 * EventRegist /event/new フォームの全フィールドをダンプする。
 *
 * 実行方法:
 *   node scripts/dump-eventregist-fields.mjs
 *
 * 動作:
 *   1. Chromium を headed で起動（macOS は実 Chrome）
 *   2. https://eventregist.com/login を開く
 *   3. ユーザーが Google ログインを終えるまで待機（B Cookie が出るまでポーリング）
 *   4. /event/new に遷移してフォームを描画
 *   5. input/textarea/select/button を全部 JSON にダンプ
 *   6. Cookie もまとめて保存（次回からのセッション再利用用）
 *
 * 出力:
 *   - form-fields-dump-eventregist.json
 *   - eventregist-cookies.json
 */

import { chromium } from 'playwright';
import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

const TIMEOUT_LOGIN_MS = 5 * 60 * 1000;  // 5分以内に手動ログインしてもらう

async function main() {
  const browser = await chromium.launch({
    headless: false,
    ...(process.platform === 'darwin' && { channel: 'chrome' }),
  });
  const context = await browser.newContext({
    locale: 'ja-JP',
    viewport: { width: 1280, height: 900 },
  });
  const page = await context.newPage();

  console.log('▶︎ EventRegist のログインページを開きます。');
  console.log('  ブラウザで Google ログインを完了してください（最大 5 分待ちます）...');
  await page.goto('https://eventregist.com/login', { waitUntil: 'domcontentloaded' });

  // 'B' Cookie が立つまで待つ（Yahoo セッション）
  const start = Date.now();
  let logged = false;
  while (Date.now() - start < TIMEOUT_LOGIN_MS) {
    const cookies = await context.cookies('https://eventregist.com');
    const hasB = cookies.find((c) => c.name === 'B');
    const hasE = cookies.find((c) => c.name === 'E');
    if (hasB && hasE) {
      logged = true;
      break;
    }
    await page.waitForTimeout(2000);
  }
  if (!logged) {
    console.error('✗ ログイン未完了のままタイムアウト');
    await browser.close();
    process.exit(1);
  }
  console.log('✓ ログイン検知（B/E Cookie あり）');

  // Cookie 保存
  const cookies = await context.cookies('https://eventregist.com');
  writeFileSync(
    join(ROOT, 'eventregist-cookies.json'),
    JSON.stringify(cookies, null, 2),
    'utf-8'
  );
  console.log(`✓ Cookie 保存: eventregist-cookies.json (${cookies.length} 件)`);

  // /event/new へ
  await page.goto('https://eventregist.com/event/new', {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });
  await page.waitForTimeout(3000);
  console.log(`▶︎ /event/new に遷移: ${page.url()}`);

  // フォームダンプ
  const dump = await page.evaluate(() => {
    const fields = [...document.querySelectorAll('input, textarea, select')]
      .map((el) => ({
        tag: el.tagName.toLowerCase(),
        type: el.type || '',
        name: el.name || '',
        id: el.id || '',
        placeholder: el.placeholder || '',
        ariaLabel: el.getAttribute('aria-label') || '',
        required: !!el.required,
        visible: !!el.offsetParent,
        labelText: (() => {
          if (el.id) {
            const lab = document.querySelector(`label[for="${el.id}"]`);
            if (lab) return lab.innerText.trim().slice(0, 80);
          }
          const parentLabel = el.closest('label');
          return parentLabel ? parentLabel.innerText.trim().slice(0, 80) : '';
        })(),
        options: el.tagName === 'SELECT'
          ? [...el.options].slice(0, 50).map((o) => ({ value: o.value, text: o.text?.slice(0, 50) }))
          : undefined,
      }));

    const buttons = [...document.querySelectorAll('button, a[role="button"], input[type="submit"], input[type="button"]')]
      .filter((b) => b.offsetParent)
      .map((b) => ({
        tag: b.tagName.toLowerCase(),
        type: b.type || '',
        text: (b.innerText || b.value || '').trim().slice(0, 80),
        id: b.id || '',
        className: (b.className || '').toString().slice(0, 80),
        href: b.href || '',
      }))
      .filter((b) => b.text);

    const recaptcha = (() => {
      const el = document.querySelector('.g-recaptcha[data-sitekey]');
      if (el) return { type: 'inline', sitekey: el.getAttribute('data-sitekey') };
      const iframe = document.querySelector('iframe[src*="recaptcha"]');
      if (iframe) {
        const m = iframe.src.match(/[?&]k=([^&]+)/);
        return { type: 'iframe', sitekey: m ? m[1] : null, src: iframe.src };
      }
      return null;
    })();

    return {
      url: location.href,
      title: document.title,
      fields,
      buttons,
      recaptcha,
    };
  });

  const out = join(ROOT, 'form-fields-dump-eventregist.json');
  writeFileSync(out, JSON.stringify(dump, null, 2), 'utf-8');

  console.log(`✓ フォームダンプ保存: ${out}`);
  console.log(`  入力フィールド: ${dump.fields.length} 件`);
  console.log(`  ボタン: ${dump.buttons.length} 件`);
  console.log(`  reCAPTCHA: ${dump.recaptcha ? `あり (sitekey=${dump.recaptcha.sitekey?.slice(0, 30)}...)` : 'なし'}`);

  // 主要フィールドの抜粋表示
  const namedFields = dump.fields.filter((f) => f.name || f.id || f.placeholder);
  console.log('\n--- 名前/ID 付きフィールド（先頭 30 件） ---');
  for (const f of namedFields.slice(0, 30)) {
    console.log(`  [${f.tag}/${f.type}] name=${f.name || '-'} id=${f.id || '-'} ph=${f.placeholder || '-'} label=${f.labelText || '-'}`);
  }

  console.log('\n▶︎ 確認したらブラウザを閉じてください（10 秒待機）');
  await page.waitForTimeout(10000);
  await browser.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
