import { chromium } from 'playwright';
import 'dotenv/config';

const TARGET_TITLE = '働き方に悩む30代へ｜安定を目指すAIプログラミング体験会';

const browser = await chromium.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
});
const context = await browser.newContext();
const page = await context.newPage();

try {
  await page.goto('https://owner.techplay.jp/auth', { waitUntil: 'domcontentloaded', timeout: 30_000 });
  await page.waitForTimeout(2000);

  console.log(`[DEBUG] pre-login URL: ${page.url()}`);
  if (!page.url().includes('dashboard') && !page.url().includes('select_menu')) {
    await page.fill('#email', process.env.TECHPLAY_EMAIL);
    await page.fill('#password', process.env.TECHPLAY_PASSWORD);
    console.log('[DEBUG] credentials filled, clicking submit');
    await Promise.all([
      page.waitForNavigation({ timeout: 30_000 }).catch(() => {}),
      page.click("input[type='submit']"),
    ]);
    await page.waitForTimeout(5000);
    console.log(`[DEBUG] post-login URL: ${page.url()}`);

    // If redirect to select_menu → pick first group
    if (page.url().includes('select_menu')) {
      const firstGroup = page.locator('a[href*="select_group"], button[type="submit"]').first();
      if (await firstGroup.count() > 0) {
        await firstGroup.click();
        await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => {});
        await page.waitForTimeout(3000);
        console.log(`[DEBUG] after group select URL: ${page.url()}`);
      }
    }
  }

  await page.goto('https://owner.techplay.jp/event', { waitUntil: 'domcontentloaded', timeout: 30_000 });
  await page.waitForTimeout(5000);

  console.log(`[DEBUG] URL after goto: ${page.url()}`);
  console.log(`[DEBUG] title: ${await page.title()}`);

  // Dump first 2000 chars of body text
  const bodyText = await page.evaluate(() => document.body.innerText.slice(0, 2000));
  console.log(`[DEBUG BODY]\n${bodyText}`);

  // Dump all anchor hrefs
  const allHrefs = await page.evaluate(() => Array.from(document.querySelectorAll('a')).map(a => a.href).slice(0, 50));
  console.log(`[DEBUG HREFS]`);
  allHrefs.forEach(h => console.log(`  ${h}`));

  const links = await page.evaluate(() => {
    const results = [];
    document.querySelectorAll('a[href*="/event/"]').forEach((a) => {
      const href = a.href;
      const text = (a.textContent || '').trim();
      if (href.match(/\/event\/\d+/)) {
        results.push({ href, text: text.slice(0, 300) });
      }
    });
    return results;
  });

  console.log(`[DEBUG] found ${links.length} event links`);

  let matched = links.find((l) => l.text.includes(TARGET_TITLE) || l.text.includes(TARGET_TITLE.slice(0, 20)));
  if (!matched) {
    matched = links.find((l) => /\/event\/\d+(\/edit)?$/.test(l.href));
    if (matched) console.log('[FALLBACK] using first event link (likely latest)');
  }

  if (matched) {
    const normalized = matched.href.replace(/\/edit\/?$/, '');
    console.log(`URL=${normalized}`);
    console.log(`TEXT=${matched.text}`);
  } else {
    console.log('[NOT FOUND]');
    links.slice(0, 5).forEach((l) => console.log(`  ${l.href} — ${l.text}`));
    process.exit(1);
  }
} finally {
  await browser.close();
}
