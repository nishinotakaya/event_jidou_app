import { chromium } from 'playwright';
import dotenv from 'dotenv';
dotenv.config();

(async () => {
  const browser = await chromium.launch({
    headless: true,
    channel: 'chrome',
    args: ['--no-sandbox']
  });
  const page = await browser.newPage();

  try {
    // 1. ログインページ
    console.log('=== セミナーベース ログイン ===');
    await page.goto('https://seminarbase.com/owner/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    console.log('URL:', page.url());

    // ログインフォーム構造
    const loginFields = await page.evaluate(() => {
      return [...document.querySelectorAll('input, button, a')]
        .filter(el => el.offsetParent !== null)
        .map(el => ({
          tag: el.tagName, type: el.type, name: el.name, id: el.id,
          text: el.textContent?.trim()?.slice(0, 30),
          href: el.href?.slice(0, 80),
          placeholder: el.placeholder,
          class: el.className?.slice(0, 50)
        }));
    });
    console.log('ログインフォーム:', JSON.stringify(loginFields, null, 2));

    // ログイン実行
    const emailField = await page.locator('input[type="email"], input[name*="email" i], input[name*="mail" i]').first();
    const passField = await page.locator('input[type="password"]').first();

    if (await emailField.isVisible().catch(() => false)) {
      await emailField.fill('takaya314boxing@gmail.com');
      console.log('メール入力完了');
    }
    if (await passField.isVisible().catch(() => false)) {
      await passField.fill('TAkaya314!');
      console.log('パスワード入力完了');
    }

    await Promise.all([
      page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
      page.locator('button[type="submit"], input[type="submit"]').first().click().catch(() => {}),
    ]);
    await page.waitForTimeout(3000);
    console.log('ログイン後URL:', page.url());

    // ダッシュボードの構造を確認
    const dashLinks = await page.evaluate(() => {
      return [...document.querySelectorAll('a')]
        .filter(a => a.href && (a.href.includes('seminar') || a.href.includes('event') || a.href.includes('create') || a.href.includes('new') || a.href.includes('regist') || a.href.includes('add')))
        .map(a => ({ text: a.textContent?.trim()?.slice(0, 40), href: a.href }));
    });
    console.log('ダッシュボードリンク:', JSON.stringify(dashLinks, null, 2));

    // イベント作成ページを探す
    const createLink = dashLinks.find(l =>
      l.text?.includes('作成') || l.text?.includes('登録') || l.text?.includes('新規') ||
      l.href?.includes('create') || l.href?.includes('new') || l.href?.includes('add')
    );

    if (createLink) {
      console.log('\n=== イベント作成ページ ===');
      await page.goto(createLink.href, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      console.log('作成ページURL:', page.url());

      const formFields = await page.evaluate(() => {
        return [...document.querySelectorAll('input, select, textarea')]
          .map(el => {
            const label = el.closest('.form-group, .field, tr, label, div')?.querySelector('label, th, .label')?.textContent?.trim()?.slice(0, 30) || '';
            const options = el.tagName === 'SELECT'
              ? [...el.options].slice(0, 5).map(o => `${o.value}:${o.text.slice(0, 20)}`)
              : [];
            return {
              tag: el.tagName, type: el.type, name: el.name, id: el.id,
              required: el.required, visible: el.offsetParent !== null,
              label, options: options.length > 0 ? options : undefined,
              placeholder: el.placeholder || undefined,
            };
          })
          .filter(f => f.name || f.id);
      });
      console.log('フォーム項目:', JSON.stringify(formFields, null, 2));
    }

  } catch (e) {
    console.error('エラー:', e.message);
  } finally {
    await browser.close();
  }
})();
