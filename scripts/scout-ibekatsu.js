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
    console.log('=== イベ活 ログイン ===');
    await page.goto('https://event21.co.jp/ibekatu/login.cgi', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    console.log('URL:', page.url());

    // ログインフォーム構造
    const loginFields = await page.evaluate(() => {
      return [...document.querySelectorAll('input, button, select, textarea')]
        .map(el => ({
          tag: el.tagName, type: el.type, name: el.name, id: el.id,
          placeholder: el.placeholder,
          visible: el.offsetParent !== null,
          value: el.type === 'hidden' ? el.value?.slice(0, 30) : '',
          class: el.className?.slice(0, 50)
        }));
    });
    console.log('ログインフォーム:', JSON.stringify(loginFields, null, 2));

    // ログイン実行
    const emailField = await page.locator('input[type="email"], input[name*="email" i], input[name*="mail" i], input[type="text"]').first();
    const passField = await page.locator('input[type="password"]').first();

    if (await emailField.isVisible().catch(() => false)) {
      await emailField.fill('takaya314boxing@gmail.com');
      console.log('メール入力完了');
    }
    if (await passField.isVisible().catch(() => false)) {
      await passField.fill('Takaya314');
      console.log('パスワード入力完了');
    }

    await Promise.all([
      page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
      page.locator('button[type="submit"], input[type="submit"]').first().click().catch(() => {}),
    ]);
    await page.waitForTimeout(3000);
    console.log('ログイン後URL:', page.url());

    // ログイン後ページの構造
    const pageContent = await page.evaluate(() => {
      return {
        title: document.title,
        links: [...document.querySelectorAll('a')]
          .filter(a => a.href && a.offsetParent !== null)
          .map(a => ({ text: a.textContent?.trim()?.slice(0, 40), href: a.href?.slice(0, 100) }))
          .filter(a => a.text),
        forms: [...document.querySelectorAll('form')].map(f => ({
          action: f.action?.slice(0, 80), method: f.method,
          fields: [...f.querySelectorAll('input, select, textarea')].length
        }))
      };
    });
    console.log('ページタイトル:', pageContent.title);
    console.log('リンク:', JSON.stringify(pageContent.links.slice(0, 20), null, 2));
    console.log('フォーム:', JSON.stringify(pageContent.forms, null, 2));

    // イベント投稿ページを探す
    const createLink = pageContent.links.find(l =>
      l.text?.includes('投稿') || l.text?.includes('登録') || l.text?.includes('作成') || l.text?.includes('新規') ||
      l.href?.includes('post') || l.href?.includes('regist') || l.href?.includes('create') || l.href?.includes('new') || l.href?.includes('add')
    );

    if (createLink) {
      console.log('\n=== イベント投稿ページ ===');
      await page.goto(createLink.href, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      console.log('投稿ページURL:', page.url());

      const formFields = await page.evaluate(() => {
        return [...document.querySelectorAll('input, select, textarea')]
          .map(el => {
            const row = el.closest('tr, .form-group, div');
            const label = row?.querySelector('th, label, .label, dt, strong')?.textContent?.trim()?.slice(0, 30) || '';
            const options = el.tagName === 'SELECT'
              ? [...el.options].slice(0, 8).map(o => `${o.value}:${o.text.slice(0, 20)}`)
              : [];
            return {
              tag: el.tagName, type: el.type, name: el.name, id: el.id,
              required: el.required, visible: el.offsetParent !== null,
              label, options: options.length > 0 ? options : undefined,
              placeholder: el.placeholder || undefined,
              maxlength: el.maxLength > 0 ? el.maxLength : undefined,
            };
          })
          .filter(f => f.name || f.id);
      });
      console.log('フォーム項目:', JSON.stringify(formFields, null, 2));
    } else {
      console.log('投稿リンクが見つからないため、主要リンクを表示:');
      console.log(JSON.stringify(pageContent.links, null, 2));
    }

  } catch (e) {
    console.error('エラー:', e.message);
  } finally {
    await browser.close();
  }
})();
