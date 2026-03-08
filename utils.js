/** 汎用ユーティリティ（Peatix / Techplay 等で共有） */

export async function findVisible(page, ...selectors) {
  for (const sel of selectors) {
    const visible = await page.locator(sel).first().isVisible({ timeout: 2000 }).catch(() => false);
    if (visible) return sel;
  }
  return null;
}

export async function check404(page, site, log) {
  const title = await page.title().catch(() => '');
  const url   = page.url();
  log(`[${site}] URL: ${url} | タイトル: "${title}"`);
  if (title.includes('404') || title.includes('見つかりません') || title.includes('Not Found') || url.includes('/404')) {
    throw new Error(`ページが見つかりません (404): ${url}`);
  }
}

export async function loginWithPlaywright(page, cfg, site, log) {
  log(`[${site}] ログイン確認 → ${cfg.mypage}`);
  await page.goto(cfg.mypage, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1000);

  const url = page.url();
  const needLogin = url.includes('login') || url.includes('signin') || url.includes('sign_in');
  if (!needLogin) { log(`[${site}] ✅ ログイン済み`); return; }

  log(`[${site}] ログイン中 → ${cfg.loginUrl}`);
  await page.goto(cfg.loginUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

  const emailSel = await findVisible(page, ...cfg.emailSel.split(',').map(s => s.trim()));
  if (!emailSel) throw new Error(`[${site}] メールフィールドが見つかりません`);
  await page.fill(emailSel, cfg.email);

  const passSel = await findVisible(page, ...cfg.passSel.split(',').map(s => s.trim()));
  if (!passSel) throw new Error(`[${site}] パスワードフィールドが見つかりません`);
  await page.fill(passSel, cfg.password);

  const submitCandidates = [
    ...(cfg.submitSel ? cfg.submitSel.split(',').map(s => s.trim()) : []),
    'button[type="submit"]', 'input[type="submit"]',
  ];
  const submitSel = await findVisible(page, ...submitCandidates);
  if (!submitSel) throw new Error(`[${site}] ログインボタンが見つかりません`);

  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    page.click(submitSel),
  ]);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});

  const afterUrl = page.url();
  if (afterUrl.includes('login') || afterUrl.includes('signin') || afterUrl.includes('sign_in')) {
    throw new Error(`[${site}] ログインに失敗しました（認証情報を確認してください）`);
  }
  log(`[${site}] ✅ ログイン完了 → ${afterUrl}`);
}

export async function fillAndSubmit(page, cfg, site, content, log) {
  log(`[${site}] 投稿ページへ移動 → ${cfg.createUrl}`);
  await page.goto(cfg.createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  await check404(page, site, log);

  const currentUrl = page.url();
  if (currentUrl.includes('login') || currentUrl.includes('signin')) {
    throw new Error(`[${site}] 投稿ページへのアクセスに失敗しました（再ログインが必要かもしれません）`);
  }

  const fields = await page.evaluate(() =>
    [...document.querySelectorAll('input, textarea, select')].map(el => ({
      tag: el.tagName.toLowerCase(), type: el.type || '',
      name: el.name || '', id: el.id || '', ph: el.placeholder || '',
      required: el.required || el.getAttribute('aria-required') === 'true',
    }))
  );
  log(`[${site}] フォーム項目: ${fields.map(f => f.name || f.id || f.ph).filter(Boolean).join(', ')}`);

  const in30days = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const defaultDate = in30days.toISOString().slice(0, 10);
  const defaultDatetime = in30days.toISOString().slice(0, 16);

  for (const f of fields) {
    if (!f.required) continue;
    const sel = f.id ? `#${CSS.escape(f.id)}` : f.name ? `${f.tag}[name="${f.name}"]` : null;
    if (!sel) continue;
    const el = page.locator(sel).first();
    const visible = await el.isVisible({ timeout: 1000 }).catch(() => false);
    if (!visible) continue;
    const current = await el.inputValue().catch(() => '');
    if (current) continue;

    if (f.tag === 'select') {
      await page.evaluate((s) => {
        const el = document.querySelector(s);
        const opt = el && [...el.options].find(o => o.value && o.value !== '0' && o.value !== '');
        if (opt) el.value = opt.value;
      }, sel).catch(() => {});
      log(`[${site}] 必須select入力: ${f.name || f.id}`);
    } else if (f.type === 'datetime-local') {
      await el.fill(defaultDatetime).catch(() => {});
      log(`[${site}] 必須日時入力: ${f.name || f.id} = ${defaultDatetime}`);
    } else if (f.type === 'date') {
      await el.fill(defaultDate).catch(() => {});
      log(`[${site}] 必須日付入力: ${f.name || f.id} = ${defaultDate}`);
    } else if (f.type === 'time') {
      await el.fill('10:00').catch(() => {});
      log(`[${site}] 必須時刻入力: ${f.name || f.id} = 10:00`);
    } else if (f.type === 'number') {
      await el.fill('50').catch(() => {});
      log(`[${site}] 必須数値入力: ${f.name || f.id} = 50`);
    } else if (f.type === 'text' || f.type === '') {
      const n = (f.name + f.id + f.ph).toLowerCase();
      let val = '要確認';
      if (n.includes('place') || n.includes('venue') || n.includes('会場') || n.includes('場所')) val = 'オンライン';
      else if (n.includes('url') || n.includes('link')) val = 'https://example.com';
      else if (n.includes('email') || n.includes('mail')) val = cfg.email || 'info@example.com';
      else if (n.includes('tel') || n.includes('phone')) val = '000-0000-0000';
      await el.fill(val).catch(() => {});
      log(`[${site}] 必須テキスト入力: ${f.name || f.id} = "${val}"`);
    }
  }

  const textareaSelectors = fields
    .filter(f => f.tag === 'textarea')
    .map(f => f.name ? `textarea[name="${f.name}"]` : f.id ? `textarea[id="${f.id}"]` : null)
    .filter(Boolean);

  const contentSel = await findVisible(page, ...textareaSelectors, 'div[contenteditable="true"]', 'textarea');
  if (!contentSel) throw new Error(`[${site}] 本文フィールドが見つかりません`);
  log(`[${site}] 本文フィールド: ${contentSel}`);
  await page.fill(contentSel, content);

  const titleSel = await findVisible(page, 'input[name="title"]', 'input[id="title"]', 'input[name="name"]', 'input[id="name"]');
  if (titleSel) {
    const current = await page.inputValue(titleSel).catch(() => '');
    if (!current) {
      const titleText = content.split('\n')[0].replace(/^[#【\s]+/, '').replace(/】$/, '').slice(0, 80);
      await page.fill(titleSel, titleText);
      log(`[${site}] タイトル入力: "${titleText}"`);
    }
  }

  const submitSel = await findVisible(page,
    'button[type="submit"]', 'input[type="submit"]',
    'button:has-text("投稿")', 'button:has-text("保存")', 'button:has-text("公開")',
    'button:has-text("Submit")', 'button:has-text("Save")', 'button:has-text("Publish")',
  );
  if (!submitSel) throw new Error(`[${site}] 送信ボタンが見つかりません`);
  log(`[${site}] 送信: ${submitSel}`);

  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    page.click(submitSel),
  ]);
  await check404(page, site, log);
  log(`[${site}] ✅ 投稿完了 → ${page.url()}`);
}
