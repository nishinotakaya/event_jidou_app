/**
 * こくチーズ Step2 フォームの全フィールドをダンプ
 * 実行: node scripts/dump-kokuchpro-fields.js
 *
 * 出力: form-fields-dump.json
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
  const browser = await chromium.launch({
    headless: true,
    ...(process.platform === 'darwin' && { channel: 'chrome' }),
  });
  const page = await browser.newPage({ locale: 'ja-JP' });

  try {
    await page.goto(cfg.createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(1500);

    if (page.url().includes('login') || page.url().includes('signin')) {
      await page.fill('#LoginFormEmail', cfg.email);
      await page.fill('#LoginFormPassword', cfg.password);
      await Promise.all([
        page.waitForNavigation({ timeout: 30000 }),
        page.click('#UserLoginForm button[type="submit"]'),
      ]);
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(2000);
    }

    const hasStep1 = await page.locator('input[name="data[Event][event_type]"]').first().isVisible({ timeout: 3000 }).catch(() => false);
    if (hasStep1) {
      await page.locator('input[name="data[Event][event_type]"][value="0"]').check();
      await page.locator('input[name="data[Event][charge]"][value="0"]').check();
      await Promise.all([
        page.waitForNavigation({ timeout: 30000 }),
        page.evaluate(() => {
          const f = [...document.querySelectorAll('form')].find(fm => fm.querySelector('input[name="data[step]"]'));
          if (f) f.submit();
        }),
      ]);
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(3000);
    }

    await page.waitForTimeout(2000);

    const dump = await page.evaluate(() => {
      const els = [...document.querySelectorAll('input, textarea, select')];
      return els
        .filter(e => e.name)
        .map(e => ({
          name:    e.name,
          tag:     e.tagName.toLowerCase(),
          type:    e.type || '',
          id:      e.id || '',
          visible: e.offsetParent !== null,
          options: e.tagName === 'SELECT' ? [...e.options].map(o => ({ value: o.value, text: o.text?.slice(0, 30) })) : undefined,
        }));
    });

    const out = join(__dirname, '..', 'form-fields-dump.json');
    writeFileSync(out, JSON.stringify(dump, null, 2), 'utf-8');
    console.log('✅ 保存:', out);
    console.log('フィールド数:', dump.length);
    console.log('\n日付関連:', dump.filter(d => d.name.includes('date') || d.name.includes('time')).map(d => d.name));
    console.log('\n概要/description:', dump.filter(d => d.name.toLowerCase().includes('description') || d.name.includes('概要')));
    console.log('\ntel:', dump.filter(d => d.name.toLowerCase().includes('tel')));

  } finally {
    await browser.close();
  }
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
