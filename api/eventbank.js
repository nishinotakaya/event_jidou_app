/** EventBankプレス（30以上のメディアに自動配信） */

export const SITE_NAME = 'EventBank';

export const config = {
  loginUrl:  'https://www.eventbank.jp/index.do',
  memberUrl: 'https://www.eventbank.jp/member/main.do',
  createUrl: 'https://www.eventbank.jp/event/regist.do?act=input&md=regist',
  get uid()      { return process.env.EVENTBANK_UID || '132843'; },
  get password() { return process.env.EVENTBANK_PASSWORD || 'Takaya314'; },
};

export async function post(page, content, eventFields = {}, log) {
  const cfg = config;
  const title = (eventFields.title || content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '')).slice(0, 100) || 'イベント';

  // ===== 1. ログイン =====
  log(`[EventBank] ログインページへアクセス中...`);
  await page.goto(cfg.loginUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);

  await page.fill('input[name="uid"]', cfg.uid);
  await page.fill('input[name="passwd"]', cfg.password);
  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    page.locator('input[type="image"]').first().click(),
  ]);
  await page.waitForTimeout(1500);

  if (!page.url().includes('/member/')) {
    throw new Error('ログインに失敗しました（認証情報を確認してください）');
  }
  log(`[EventBank] ✅ ログイン完了 → ${page.url()}`);

  // ===== 2. イベント登録ページへ =====
  log(`[EventBank] 登録ページへ移動中...`);
  await page.goto(cfg.createUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);
  log(`[EventBank] 登録ページ: ${page.url()}`);

  // ===== 3. フォーム入力 =====
  const ef = eventFields;
  const now = new Date();
  const in30 = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  // 日時の計算
  const startDate = ef.startDate ? new Date(ef.startDate.replace(/\//g, '-')) : in30;
  const endDate = ef.endDate ? new Date(ef.endDate.replace(/\//g, '-')) : startDate;
  const [startH, startM] = (ef.startTime || '10:00').split(':').map(Number);
  const [endH, endM] = (ef.endTime || '12:00').split(':').map(Number);

  // フォーマットヘルパー
  const fmtDate = (d) => `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;

  await page.evaluate(({
    title, content, startDate, endDate, startH, startM, endH, endM, fmtDateStr, place, now,
  }) => {
    const setVal = (name, value) => {
      const el = document.querySelector(`[name="${name}"]`);
      if (!el) return;
      if (el.tagName === 'SELECT') {
        for (const o of el.options) {
          if (o.value === String(value)) { el.value = o.value; return; }
        }
      } else if (el.tagName === 'TEXTAREA') {
        el.value = value;
      } else {
        el.value = value;
      }
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };

    const checkRadio = (name, value) => {
      const el = document.querySelector(`input[name="${name}"][value="${value}"]`);
      if (el) el.checked = true;
    };

    const checkCheckbox = (id) => {
      const el = document.getElementById(id);
      if (el && !el.checked) el.checked = true;
    };

    // イベント名
    setVal('name', title);

    // イベント名ふりがな（タイトルからカタカナ変換は難しいので簡易版）
    setVal('kana', title);

    // イベント種別: セミナー・講演会 (typek16)
    checkCheckbox('typek16');

    // ターゲット: 一般 (target checkbox)
    const targets = document.querySelectorAll('input[name="target"]');
    if (targets.length > 0) targets[0].checked = true;

    // 開催日（hidden fields）
    setVal('fromyear', startDate.year);
    setVal('frommonth', startDate.month);
    setVal('fromday', startDate.day);
    setVal('toyear', endDate.year);
    setVal('tomonth', endDate.month);
    setVal('today', endDate.day);

    // 開催日テキスト
    setVal('date', fmtDateStr);

    // 時刻
    setVal('fromhour', startH);
    setVal('fromminute', startM);
    setVal('tohour', endH);
    setVal('tominute', endM);

    // 会場
    setVal('placename', place || 'オンライン');

    // 都道府県（13=東京都）
    setVal('pref', '13');

    // 屋内
    checkRadio('inoutdoor', '0');

    // 料金: 無料
    checkRadio('chargetype', '0');

    // 動員人数: 100人未満
    setVal('nummobil', '0');

    // PR文
    const summary = content.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();
    setVal('promoword', summary.slice(0, 40));

    // イベント紹介文
    setVal('introduction', content);

    // 公開日（today）
    setVal('publishyear', now.year);
    setVal('publishmonth', now.month);
    setVal('publishday', now.day);

    // 登録者名
    setVal('inputlastname', '西野');
    setVal('inputfirstname', '貴也');
  }, {
    title,
    content,
    startDate: { year: startDate.getFullYear(), month: startDate.getMonth() + 1, day: startDate.getDate() },
    endDate: { year: endDate.getFullYear(), month: endDate.getMonth() + 1, day: endDate.getDate() },
    startH, startM, endH, endM,
    fmtDateStr: fmtDate(startDate),
    place: ef.place || 'オンライン',
    now: { year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate() },
  });

  log(`[EventBank] フォーム入力完了`);

  // ===== 4. 日付カレンダー操作（hidden fields の日付セット） =====
  // EventBankはカレンダーUIで日付をセットし、hidden fieldsに反映する
  // カレンダーが無い場合はhiddenに直接セットする
  await page.evaluate(({ sy, sm, sd, ey, em, ed }) => {
    const setHidden = (name, val) => {
      const el = document.querySelector(`input[name="${name}"]`);
      if (el) el.value = String(val);
    };
    setHidden('fromyear', sy);
    setHidden('frommonth', sm);
    setHidden('fromday', sd);
    setHidden('toyear', ey);
    setHidden('tomonth', em);
    setHidden('today', ed);
  }, {
    sy: startDate.getFullYear(), sm: startDate.getMonth() + 1, sd: startDate.getDate(),
    ey: endDate.getFullYear(), em: endDate.getMonth() + 1, ed: endDate.getDate(),
  });

  // ===== 5. 送信（form.submit() — submitボタンがないフォーム） =====
  log(`[EventBank] フォーム送信（act=confirm）...`);
  await page.evaluate(() => {
    const form = document.getElementById('eventManagerForm');
    if (!form) throw new Error('eventManagerForm が見つかりません');
    // act を confirm にセットして確認画面へ
    const actField = form.querySelector('input[name="act"]');
    if (actField) actField.value = 'confirm';
    form.submit();
  });
  await page.waitForNavigation({ timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2000);

  // ===== 6. 確認画面 → 最終送信 =====
  const afterUrl = page.url();
  log(`[EventBank] 送信後: ${afterUrl}`);

  // 確認画面でエラーチェック
  const confirmErrors = await page.evaluate(() => {
    const reds = [...document.querySelectorAll('font[color="red"], .error, .err, [style*="color:red"]')];
    return reds.map(el => el.textContent?.trim()).filter(Boolean).join(' / ');
  });
  if (confirmErrors) {
    log(`[EventBank] ⚠️ バリデーションメッセージ: ${confirmErrors}`);
  }

  // 確認画面→最終登録（form.submit で act=regist）
  const hasConfirmForm = await page.locator('#eventManagerForm, form[action*="regist"]').count();
  if (hasConfirmForm > 0) {
    log(`[EventBank] 確認画面から最終登録...`);
    await page.evaluate(() => {
      const form = document.getElementById('eventManagerForm') || document.querySelector('form[action*="regist"]');
      if (!form) return;
      const actField = form.querySelector('input[name="act"]');
      if (actField) actField.value = 'regist';
      form.submit();
    });
    await page.waitForNavigation({ timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(2000);
  }

  // ===== 7. 結果確認 =====
  const finalUrl = page.url();
  const pageText = await page.evaluate(() => document.body?.textContent?.slice(0, 500) || '');

  if (pageText.includes('登録が完了') || pageText.includes('ありがとう') || pageText.includes('完了') || finalUrl.includes('complete') || finalUrl.includes('finish')) {
    log(`[EventBank] ✅ 投稿完了 → ${finalUrl}`);
  } else if (finalUrl.includes('regist')) {
    // まだ登録ページにいる場合、エラーを確認
    const errors = await page.evaluate(() => {
      const reds = [...document.querySelectorAll('.error, .err, [style*="color:red"], [style*="color: red"], font[color="red"]')];
      return reds.map(el => el.textContent?.trim()).filter(Boolean).join(' / ');
    });
    if (errors) {
      throw new Error(`バリデーションエラー: ${errors}`);
    }
    log(`[EventBank] ⚠️ 登録ページに留まっています（確認画面かもしれません）: ${finalUrl}`);
  } else {
    log(`[EventBank] ✅ 投稿完了 → ${finalUrl}`);
  }
}
