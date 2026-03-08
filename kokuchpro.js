/** こくチーズ専用（TinyMCE + 多段フォーム対応） */

export const SITE_NAME = 'こくチーズ';

export const config = {
  loginUrl:  process.env.KOKUCH_LOGIN_URL     || 'https://www.kokuchpro.com/auth/login/',
  mypage:    process.env.CONPASS_KOKUCIZE_URL || 'https://www.kokuchpro.com/mypage/',
  createUrl: process.env.KOKUCH_CREATE_URL    || 'https://www.kokuchpro.com/regist/',
  email:     process.env.CONPASS__KOKUCIZE_MAIL,
  password:  process.env.CONPASS_KOKUCIZE_PASSWORD,
  emailSel:  '#LoginFormEmail, input[name="data[LoginForm][email]"]',
  passSel:   '#LoginFormPassword, input[name="data[LoginForm][password]"]',
  submitSel: '#UserLoginForm button[type="submit"]',
};

export async function post(page, content, eventFields = {}, log) {
  const cfg = config;
  const title = content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '').slice(0, 80) || 'イベント';

  log(`[こくチーズ] /regist/ にアクセス中...`);
  await page.goto(cfg.createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);

  if (page.url().includes('login') || page.url().includes('signin')) {
    log(`[こくチーズ] ログイン中...`);
    await page.fill('#LoginFormEmail', cfg.email);
    await page.fill('#LoginFormPassword', cfg.password);
    await Promise.all([
      page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
      page.click('#UserLoginForm button[type="submit"]'),
    ]);
    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
    if (page.url().includes('login') || page.url().includes('signin')) {
      throw new Error('ログインに失敗しました（認証情報を確認してください）');
    }
    log(`[こくチーズ] ✅ ログイン完了 → ${page.url()}`);
  } else {
    log(`[こくチーズ] ✅ ログイン済み`);
  }

  const hasStep1 = await page.locator('input[name="data[Event][event_type]"]').first().isVisible({ timeout: 2000 }).catch(() => false);
  if (hasStep1) {
    log(`[こくチーズ] Step1: イベント種別・参加費選択`);
    await page.locator('input[name="data[Event][event_type]"][value="0"]').check().catch(() => {});
    await page.locator('input[name="data[Event][charge]"][value="0"]').check().catch(() => {});

    await Promise.all([
      page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
      page.evaluate(() => {
        const mainForm = [...document.querySelectorAll('form')].find(f =>
          f.querySelector('input[name="data[step]"]')
        );
        if (mainForm) mainForm.submit();
      }),
    ]);
    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
    log(`[こくチーズ] Step2へ → ${page.url()}`);
  }

  await page.waitForTimeout(2000);

  const allFields = await page.evaluate(() =>
    [...document.querySelectorAll('input, textarea, select')]
      .filter(el => el.name)
      .map(el => `${el.tagName.toLowerCase()}[${el.name}](${el.type||''})[vis:${el.offsetParent !== null}]`)
  );
  log(`[こくチーズ] Step2フィールド一覧: ${allFields.join(', ')}`);

  const tinyIds = await page.evaluate((html) => {
    if (typeof tinymce === 'undefined' || !tinymce.editors || tinymce.editors.length === 0) return null;
    const bodyEds = tinymce.editors.filter(ed =>
      ed.id && (ed.id.toLowerCase().includes('body') || ed.id.toLowerCase().includes('page'))
    );
    const targets = bodyEds.length > 0 ? bodyEds : [tinymce.editors[0]];
    targets.forEach(ed => { ed.setContent(html.replace(/\n/g, '<br>')); ed.save(); });
    return targets.map(ed => ed.id);
  }, content).catch(() => null);
  if (tinyIds) log(`[こくチーズ] TinyMCE入力完了: [${tinyIds.join(', ')}]`);

  const in30 = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const fmt  = (d) => `${d.getFullYear()}/${String(d.getMonth()+1).padStart(2,'0')}/${String(d.getDate()).padStart(2,'0')}`;
  const ef = eventFields;
  const ymd    = ef.startDate ? ef.startDate.replace(/-/g, '/') : fmt(in30);
  const ymdEnd = ef.endDate   ? ef.endDate.replace(/-/g, '/')   : ymd;
  const tStart = ef.startTime || '10:00';
  const tEnd   = ef.endTime   || '12:00';
  const place  = ef.place     || 'オンライン';
  const cap    = ef.capacity  || '50';
  const tel    = ef.tel       || '000-0000-0000';

  const setField = async (name, val) => {
    await page.evaluate(([n, v]) => {
      const el = document.querySelector(`[name="${n}"]`);
      if (!el) return;
      let proto;
      if (el.tagName === 'SELECT') proto = HTMLSelectElement.prototype;
      else if (el.tagName === 'TEXTAREA') proto = HTMLTextAreaElement.prototype;
      else proto = HTMLInputElement.prototype;
      const nativeSet = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
      if (nativeSet) nativeSet.call(el, v); else el.value = v;
      ['input', 'change', 'blur'].forEach(ev => el.dispatchEvent(new Event(ev, { bubbles: true })));
    }, [name, val]).catch(() => {});
  };

  const setDateField = async (name, dateSlash) => {
    const [yr, mo, dy] = dateSlash.split('/');
    await setField(name, dateSlash);
    await page.evaluate(([base, y, m, d]) => {
      const setOpt = (n, v) => {
        const el = document.querySelector(`[name="${n}"]`);
        if (!el) return;
        const ival = parseInt(v);
        if (el.tagName === 'SELECT') {
          const opt = [...el.options].find(o => parseInt(o.value) === ival);
          if (opt) { el.value = opt.value; el.dispatchEvent(new Event('change', {bubbles:true})); }
        } else {
          el.value = String(ival).padStart(el.name.includes('year') ? 4 : 2, '0');
          ['input','change','blur'].forEach(e => el.dispatchEvent(new Event(e, {bubbles:true})));
        }
      };
      setOpt(`${base}[year]`, y); setOpt(`${base}[month]`, m); setOpt(`${base}[day]`, d);
    }, [name, yr, mo, dy]).catch(() => {});
    const loc = page.locator(`[name="${name}"]`).first();
    if (await loc.isVisible({ timeout: 400 }).catch(() => false)) {
      await loc.click().catch(() => {});
      await loc.fill(dateSlash).catch(() => {});
      await loc.press('Tab').catch(() => {});
    }
  };

  const setTimeField = async (name, timeStr) => {
    const [hr, mn] = timeStr.split(':');
    await setField(name, timeStr);
    await page.evaluate(([base, h, m]) => {
      const setOpt = (n, v) => {
        const el = document.querySelector(`[name="${n}"]`);
        if (!el) return;
        const ival = parseInt(v);
        if (el.tagName === 'SELECT') {
          const opt = [...el.options].find(o => parseInt(o.value) === ival);
          if (opt) { el.value = opt.value; el.dispatchEvent(new Event('change', {bubbles:true})); }
        }
      };
      setOpt(`${base}[hour]`, h); setOpt(`${base}[min]`, m); setOpt(`${base}[meridian]`, parseInt(h) >= 12 ? 'pm' : 'am');
    }, [name, hr, mn]).catch(() => {});
  };

  const summary = content.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 79);
  await setField('data[Event][name]', title);
  await setField('data[Event][description]', summary);
  const descLoc = page.locator('[name="data[Event][description]"]').first();
  if (await descLoc.isVisible({ timeout: 500 }).catch(() => false)) {
    await descLoc.fill(summary).catch(() => {});
  }
  log(`[こくチーズ] イベント名: "${title}" / 概要: "${summary.slice(0, 20)}..."`);

  await page.evaluate((s) => {
    const el = document.querySelector(s);
    if (!el) return;
    const opt = [...el.options].find(o => o.value && o.value !== '0' && o.value !== '');
    if (opt) { el.value = opt.value; el.dispatchEvent(new Event('change', { bubbles: true })); }
  }, 'select[name="data[Event][genre]"]').catch(() => {});
  await page.waitForTimeout(600);
  await page.evaluate((s) => {
    const el = document.querySelector(s);
    if (!el) return;
    const opt = [...el.options].find(o => o.value && o.value !== '0' && o.value !== '');
    if (opt) { el.value = opt.value; el.dispatchEvent(new Event('change', { bubbles: true })); }
  }, 'select[name="data[Event][genre_sub]"]').catch(() => {});

  const startMs = new Date(ymd.replace(/\//g, '-')).getTime();
  const entry7  = fmt(new Date(startMs - 7  * 24 * 60 * 60 * 1000));
  const entry1  = fmt(new Date(startMs - 1  * 24 * 60 * 60 * 1000));

  await setDateField('data[EventDate][start_date_date]', ymd);
  await setTimeField('data[EventDate][start_date_time]', tStart);
  await setDateField('data[EventDate][end_date_date]', ymdEnd);
  await setTimeField('data[EventDate][end_date_time]', tEnd);
  await setDateField('data[EventDate][entry_start_date_date]', entry7);
  await setTimeField('data[EventDate][entry_start_date_time]', '00:00');
  await setDateField('data[EventDate][entry_end_date_date]', entry1);
  await setTimeField('data[EventDate][entry_end_date_time]', '23:59');

  await setField('data[EventDate][total_capacity]', cap);
  await setField('data[Event][place]', place);
  await page.evaluate(() => {
    const el = document.querySelector('select[name="data[Event][country]"]');
    if (el) { el.value = 'JPN'; el.dispatchEvent(new Event('change', { bubbles: true })); }
  }).catch(() => {});
  await setField('data[Event][tel]', tel);
  await setField('data[Event][email]', cfg.email);

  const fieldValues = await page.evaluate(() => {
    const names = [
      'data[Event][name]', 'data[Event][description]',
      'data[EventDate][start_date_date]', 'data[EventDate][start_date_time]',
      'data[EventDate][end_date_date]', 'data[EventDate][end_date_time]',
      'data[EventDate][entry_start_date_date]', 'data[EventDate][entry_end_date_date]',
      'data[EventDate][total_capacity]', 'data[Event][place]',
    ];
    return names.map(n => {
      const el = document.querySelector(`[name="${n}"]`);
      return `${n.split('][').pop().replace(']','')}="${el ? el.value.slice(0,30) : 'NOT_FOUND'}"`;
    }).join(', ');
  });
  log(`[こくチーズ] 入力値確認: ${fieldValues}`);

  log(`[こくチーズ] 必須フィールド入力完了`);

  const submitted = await page.evaluate(() => {
    const mainForm = [...document.querySelectorAll('form')].find(f => !f.classList.contains('navbar-form'));
    if (!mainForm) return false;
    const btn = mainForm.querySelector('button[type="submit"], input[type="submit"]');
    const btnText = btn ? btn.textContent.trim() : '(不明)';
    if (btn) { btn.click(); return btnText; }
    mainForm.submit();
    return 'form.submit()';
  });
  if (!submitted) throw new Error('送信ボタンが見つかりません');
  log(`[こくチーズ] 送信: "${submitted}"`);
  await page.waitForNavigation({ timeout: 30000 }).catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});

  if (page.url().includes('/regist/')) {
    const errors = await page.evaluate(() =>
      [...document.querySelectorAll('.error-message, [class*="error"]')]
        .map(el => el.textContent.trim()).filter(Boolean).join(' / ')
    );
    throw new Error(`登録失敗（バリデーションエラー）: ${errors || '不明'}`);
  }
  log(`[こくチーズ] ✅ 投稿完了 → ${page.url()}`);
}
