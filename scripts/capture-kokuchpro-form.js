/**
 * こくチーズ登録フォームのネットワーク解析スクリプト
 * 実行: node scripts/capture-kokuchpro-form.js
 *
 * Step2フォームの全フィールド名をダンプし、送信時のPOST bodyをキャプチャして
 * captured-form-data.json に保存します。
 */

import 'dotenv/config';
import { chromium } from 'playwright';
import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const cfg = {
  createUrl: process.env.KOKUCH_CREATE_URL || 'https://www.kokuchpro.com/regist/',
  email:     process.env.CONPASS__KOKUCIZE_MAIL,
  password:  process.env.CONPASS_KOKUCIZE_PASSWORD,
};

async function main() {
  console.log('🚀 ブラウザ起動（ヘッドレス: false = 画面表示）...');
  const browser = await chromium.launch({
    channel: process.platform === 'darwin' ? 'chrome' : undefined,
    headless: false,
    slowMo:   100,
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    locale: 'ja-JP',
  });

  let capturedPost = null;

  // ネットワークリクエストをインターセプト
  await context.route('**/*', async (route) => {
    const request = route.request();
    if (request.method() === 'POST' && request.url().includes('regist')) {
      try {
        const postData = request.postData();
        if (postData) {
          // application/x-www-form-urlencoded をパース
          const params = new URLSearchParams(postData);
          const obj = {};
          for (const [k, v] of params) {
            obj[k] = v;
          }
          capturedPost = obj;
          console.log('\n📤 キャプチャしたPOSTパラメータ:', Object.keys(obj).length, '個');
        }
      } catch (e) {
        console.error('POST解析エラー:', e);
      }
    }
    await route.continue();
  });

  const page = await context.newPage();

  try {
    // 1. ログイン & Step2へ
    console.log('1. /regist/ にアクセス...');
    await page.goto(cfg.createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);

    if (page.url().includes('login') || page.url().includes('signin')) {
      console.log('2. ログイン中...');
      await page.fill('#LoginFormEmail', cfg.email);
      await page.fill('#LoginFormPassword', cfg.password);
      await Promise.all([
        page.waitForNavigation({ timeout: 30000 }),
        page.click('#UserLoginForm button[type="submit"]'),
      ]);
      await page.waitForLoadState('networkidle', { timeout: 20000 });
    }

    const hasStep1 = await page.locator('input[name="data[Event][event_type]"]').first().isVisible({ timeout: 3000 }).catch(() => false);
    if (hasStep1) {
      console.log('3. Step1 送信...');
      await page.locator('input[name="data[Event][event_type]"][value="0"]').check();
      await page.locator('input[name="data[Event][charge]"][value="0"]').check();
      await Promise.all([
        page.waitForNavigation({ timeout: 30000 }),
        page.evaluate(() => {
          const f = [...document.querySelectorAll('form')].find(fm => fm.querySelector('input[name="data[step]"]'));
          if (f) f.submit();
        }),
      ]);
      await page.waitForLoadState('networkidle', { timeout: 20000 });
    }

    await page.waitForTimeout(3000);

    // 4. Step2の全フォームフィールドをダンプ
    const formFields = await page.evaluate(() => {
      const inputs = [...document.querySelectorAll('input, textarea, select')];
      return inputs
        .filter(el => el.name)
        .map(el => ({
          tag:   el.tagName.toLowerCase(),
          name:  el.name,
          type:  el.type || '',
          id:    el.id || '',
          value: el.tagName === 'SELECT' ? el.options[el.selectedIndex]?.value : (el.value || '').slice(0, 50),
        }));
    });

    const outPath = join(__dirname, '..', 'captured-form-fields.json');
    writeFileSync(outPath, JSON.stringify(formFields, null, 2), 'utf-8');
    console.log('\n📋 フォームフィールド一覧を保存:', outPath);

    // 5. 手動でフォームを入力して送信するよう促す（または自動で入力して送信）
    console.log('\n⏳ フォームに手動で値を入力して「送信」をクリックしてください。');
    console.log('   送信されるとPOSTデータをキャプチャして保存します。');
    console.log('   30秒後に自動終了します。\n');

    // 30秒待機（ユーザーが手動で送信する時間）
    await page.waitForTimeout(30000);

  } finally {
    await browser.close();
  }

  if (capturedPost) {
    const savePath = join(__dirname, '..', 'captured-post-data.json');
    writeFileSync(savePath, JSON.stringify(capturedPost, null, 2), 'utf-8');
    console.log('\n✅ POSTデータを保存:', savePath);
    console.log('パラメータ例:', Object.keys(capturedPost).slice(0, 20).join(', '), '...');
  } else {
    console.log('\n⚠️ POSTデータはキャプチャされませんでした。手動で送信を実行しましたか？');
  }
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
