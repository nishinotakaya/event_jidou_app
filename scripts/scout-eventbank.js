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
    // 1. ログインページにアクセス
    console.log('=== EventBankプレス ログインページ ===');
    await page.goto('https://www.eventbank.jp/index.do', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    console.log('URL:', page.url());

    // ログインフォームの構造を確認
    const loginFields = await page.evaluate(() => {
      return [...document.querySelectorAll('input, select, textarea, button')]
        .filter(el => el.offsetParent !== null || el.type === 'hidden')
        .map(el => ({
          tag: el.tagName, type: el.type, name: el.name, id: el.id,
          placeholder: el.placeholder, value: el.type === 'hidden' ? el.value : '',
          class: el.className?.slice(0, 50)
        }));
    });
    console.log('ログインフォーム:', JSON.stringify(loginFields, null, 2));

    // ログイン実行
    console.log('\n=== ログイン実行 ===');
    // ID/パスワードフィールドを探す
    const idField = await page.locator('input[name*="id" i], input[name*="user" i], input[name*="login" i], input[type="text"]').first();
    const passField = await page.locator('input[type="password"]').first();

    if (await idField.isVisible().catch(() => false)) {
      await idField.fill('132843');
      console.log('ID入力完了');
    }
    if (await passField.isVisible().catch(() => false)) {
      await passField.fill('Takaya314');
      console.log('パスワード入力完了');
    }

    // ログインボタンクリック
    await Promise.all([
      page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
      page.locator('button[type="submit"], input[type="submit"], input[type="image"]').first().click(),
    ]);
    await page.waitForTimeout(2000);
    console.log('ログイン後URL:', page.url());

    // 2. イベント登録ページにアクセス
    console.log('\n=== イベント登録フォーム ===');
    await page.goto('https://www.eventbank.jp/event/regist.do?act=input&md=regist', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    console.log('登録ページURL:', page.url());

    // フォーム構造を取得
    const formFields = await page.evaluate(() => {
      return [...document.querySelectorAll('input, select, textarea')]
        .map(el => {
          const label = el.closest('tr')?.querySelector('th, label')?.textContent?.trim()?.slice(0, 30) || '';
          const options = el.tagName === 'SELECT'
            ? [...el.options].slice(0, 5).map(o => `${o.value}:${o.text.slice(0, 20)}`)
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

    // ページのHTML構造を確認（主要な部分）
    const pageStructure = await page.evaluate(() => {
      const forms = [...document.querySelectorAll('form')];
      return forms.map(f => ({
        action: f.action, method: f.method, id: f.id,
        fieldCount: f.querySelectorAll('input, select, textarea').length
      }));
    });
    console.log('\nフォーム一覧:', JSON.stringify(pageStructure, null, 2));

  } catch (e) {
    console.error('エラー:', e.message);
  } finally {
    await browser.close();
  }
})();
