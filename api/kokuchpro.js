/** こくチーズ専用（TinyMCE + jQuery datepicker 多段フォーム対応） */

import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const SITE_NAME = 'こくチーズ';

export const config = {
  loginUrl:  process.env.KOKUCH_LOGIN_URL     || 'https://www.kokuchpro.com/auth/login/',
  mypage:    process.env.CONPASS_KOKUCIZE_URL || 'https://www.kokuchpro.com/mypage/',
  createUrl: process.env.KOKUCH_CREATE_URL    || 'https://www.kokuchpro.com/regist/',
  // email/password はpost()内で都度読む（ESモジュール初期化順序の問題でdotenv前に評価されるため）
  get email()    { return process.env.CONPASS__KOKUCIZE_MAIL; },
  get password() { return process.env.CONPASS_KOKUCIZE_PASSWORD; },
  emailSel:  '#LoginFormEmail, input[name="data[LoginForm][email]"]',
  passSel:   '#LoginFormPassword, input[name="data[LoginForm][password]"]',
  submitSel: '#UserLoginForm button[type="submit"]',
};

export async function post(page, content, eventFields = {}, log) {
  const cfg = config;
  const title = (eventFields.title || eventFields.name || content.split('\n')[0].replace(/^[#【\s「『]+/, '').replace(/[】』」\s]+$/, '')).toString().slice(0, 80) || 'イベント';

  // ===== 1. ログイン =====
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

  // ===== 2. Step1: イベント種別・参加費 =====
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

  // ===== 3. Step2フォームの読み込み待ち =====
  await page.waitForTimeout(2500);

  // フィールド一覧をログ（デバッグ）
  const allFields = await page.evaluate(() =>
    [...document.querySelectorAll('input, textarea, select')]
      .filter(el => el.name)
      .map(el => `${el.tagName.toLowerCase()}[${el.name}](${el.type || el.tagName})[vis:${el.offsetParent !== null}]`)
  );
  log(`[こくチーズ] Step2フィールド一覧: ${allFields.join(', ')}`);

  // ===== 4. 日付・時刻の計算 =====
  const in30 = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const fmtDash = (d) => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  const ef = eventFields;
  const ymdDash    = ef.startDate ? ef.startDate.replace(/\//g, '-') : fmtDash(in30);
  const ymdEndDash = ef.endDate   ? ef.endDate.replace(/\//g, '-')   : ymdDash;
  const tStart = (ef.startTime || '10:00').replace(/^(\d):/, '0$1:');
  const tEnd   = (ef.endTime   || '12:00').replace(/^(\d):/, '0$1:');
  const place  = ef.place    || 'オンライン';
  const cap    = ef.capacity || '50';
  const telRaw = ef.tel || '03-1234-5678';
  const tel = /^\d{2,4}-\d{4}-\d{4}$/.test(telRaw)
    ? telRaw
    : telRaw.replace(/\D/g, '').replace(/^(\d{2,4})(\d{4})(\d{4})$/, '$1-$2-$3') || '03-1234-5678';
  const startMs = new Date(ymdDash).getTime();
  const entry7  = fmtDash(new Date(startMs - 7 * 24 * 60 * 60 * 1000));
  const entry1  = fmtDash(new Date(startMs - 1 * 24 * 60 * 60 * 1000));

  const summary   = content.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();
  const summary80 = [...summary].slice(0, 80).join('') || 'イベントのご案内です。';

  // ===== 5. TinyMCE 本文入力（body_html のみ） =====
  const tinyResult = await page.evaluate((html) => {
    if (typeof tinymce === 'undefined' || !tinymce.editors || tinymce.editors.length === 0) return [];
    const results = [];
    tinymce.editors.forEach(ed => {
      const id = (ed.id || '').toLowerCase();
      // body/page/html を含むエディタが本文欄
      if (id.includes('body') || id.includes('page') || id.includes('html')) {
        ed.setContent(html.replace(/\n/g, '<br>'));
        ed.save();
        results.push({ id: ed.id, role: 'body' });
      } else {
        results.push({ id: ed.id, role: 'other' });
      }
    });
    return results;
  }, content).catch(() => []);
  if (tinyResult.length > 0) log(`[こくチーズ] TinyMCEエディタ: ${JSON.stringify(tinyResult)}`);

  // ===== 6. 全フィールドをpage.evaluate で一括入力 =====
  const fillResult = await page.evaluate(({
    title, summary80, ymdDash, ymdEndDash, entry7, entry1,
    tStart, tEnd, cap, place, zoomUrl, tel, email
  }) => {
    const logs = [];
    // jQuery参照（window.jQuery / window.$ 両方試す）
    const $ = window.jQuery || window.$ || null;
    logs.push(`jQuery: ${$ ? 'OK' : 'NOT FOUND'}`);

    // hasDatepicker フィールド一覧
    const dpFields = [...document.querySelectorAll('input.hasDatepicker')].map(el => el.name || el.id);
    logs.push(`hasDatepicker: [${dpFields.join(', ')}]`);

    // --- ユーティリティ ---
    const find = (...sels) => {
      for (const s of sels) {
        try { const el = document.querySelector(s); if (el) return el; } catch (_) {}
      }
      return null;
    };

    // SELECT要素にオプション値を設定
    const setSelectOpt = (el, v) => {
      if (!el || el.tagName !== 'SELECT') return false;
      const ival = parseInt(v);
      // 完全一致
      for (const o of el.options) {
        if (o.value === String(v)) { el.value = o.value; el.dispatchEvent(new Event('change', { bubbles: true })); return true; }
      }
      // 数値一致
      for (const o of el.options) {
        if (parseInt(o.value) === ival && !isNaN(ival)) { el.value = o.value; el.dispatchEvent(new Event('change', { bubbles: true })); return true; }
      }
      return false;
    };

    // 日付フィールド設定（jQuery datepicker / direct value 両対応）
    // ymd は YYYY-MM-DD 形式（ハイフン区切り）
    const setDate = (el, ymd) => {
      if (!el) return 'NOT_FOUND';
      el.removeAttribute('disabled');
      el.removeAttribute('readonly');
      const [yr, mo, dy] = ymd.split('-').map(Number);
      // jQuery UI datepicker
      if ($ && $.fn && $.fn.datepicker && el.classList.contains('hasDatepicker')) {
        try {
          $(el).datepicker('setDate', new Date(yr, mo - 1, dy));
          const v = el.value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          return `jq:${v}`;
        } catch (e) {
          logs.push(`  jq error: ${e.message}`);
        }
      }
      // 直接セット（fallback も YYYY-MM-DD 形式）
      el.value = ymd;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      el.dispatchEvent(new Event('blur',  { bubbles: true }));
      return `direct:${el.value}`;
    };

    // 時刻フィールド設定（text input / select 両対応）
    const setTime = (baseName, timeStr) => {
      const [h, m] = timeStr.split(':');
      const el = find(`[name="${baseName}"]`);
      if (el) {
        if (el.tagName === 'SELECT') {
          setSelectOpt(el, timeStr) || setSelectOpt(el, `${parseInt(h)}:${m}`) || setSelectOpt(el, h);
          return `select:${el.value}`;
        }
        el.value = timeStr;
        el.dispatchEvent(new Event('input',  { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return `input:${el.value}`;
      }
      // CakePHP hour/min 個別SELECT
      const hEl = find(`[name="${baseName}[hour]"]`);
      const mEl = find(`[name="${baseName}[min]"]`);
      if (hEl) setSelectOpt(hEl, h);
      if (mEl) setSelectOpt(mEl, m);
      return `sub:${hEl?.value}:${mEl?.value}`;
    };

    // テキスト/テキストエリアに直接セット
    const setVal = (el, v) => {
      if (!el) return false;
      el.removeAttribute('disabled');
      el.removeAttribute('readonly');
      // React/Vueのネイティブsetter対策
      const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
      if (setter) setter.call(el, String(v));
      else el.value = String(v);
      el.dispatchEvent(new Event('input',  { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    };

    // === イベント名 ===
    const nameEl = find('#EventName', '[name="data[Event][name]"]');
    setVal(nameEl, title);
    logs.push(`name: ${nameEl ? `"${nameEl.value.slice(0, 30)}"` : 'NOT_FOUND'}`);

    // === 概要（TinyMCEが管理していない通常textareaのみ） ===
    const descEl = find('#EventDescription', '[name="data[Event][description]"]');
    if (descEl) {
      // TinyMCEが管理しているかチェック
      const hasTiny = typeof tinymce !== 'undefined' && tinymce.get && tinymce.get(descEl.id);
      if (hasTiny) {
        // TinyMCEで設定
        hasTiny.setContent(summary80);
        hasTiny.save();
        logs.push(`description: TinyMCE設定 ${summary80.length}文字`);
      } else {
        setVal(descEl, summary80);
        logs.push(`description: direct ${descEl.value.length}文字 = "${descEl.value.slice(0, 30)}"`);
      }
    } else {
      logs.push('description: NOT_FOUND');
    }

    // === ジャンル ===
    const genreEl = find('[name="data[Event][genre]"]', '#EventGenre');
    if (genreEl && genreEl.tagName === 'SELECT') {
      const opt = [...genreEl.options].find(o => o.value && o.value !== '' && o.value !== '0');
      if (opt) { genreEl.value = opt.value; genreEl.dispatchEvent(new Event('change', { bubbles: true })); }
    }

    // === 開催日時 ===
    const r1 = setDate(find('#EventDateStartDateDate', '[name="data[EventDate][start_date_date]"]'), ymdDash);
    logs.push(`start_date: ${r1}`);
    const r2 = setDate(find('#EventDateEndDateDate',   '[name="data[EventDate][end_date_date]"]'),   ymdEndDash);
    logs.push(`end_date: ${r2}`);
    logs.push(`start_time: ${setTime('data[EventDate][start_date_time]', tStart)}`);
    logs.push(`end_time: ${setTime('data[EventDate][end_date_time]', tEnd)}`);

    // === 募集期間 ===
    const r3 = setDate(find('#EventDateEntryStartDateDate', '[name="data[EventDate][entry_start_date_date]"]'), entry7);
    logs.push(`entry_start: ${r3}`);
    const r4 = setDate(find('#EventDateEntryEndDateDate',   '[name="data[EventDate][entry_end_date_date]"]'),   entry1);
    logs.push(`entry_end: ${r4}`);
    logs.push(`entry_start_time: ${setTime('data[EventDate][entry_start_date_time]', '00:00')}`);
    logs.push(`entry_end_time: ${setTime('data[EventDate][entry_end_date_time]', '23:59')}`);

    // === 定員・会場・国・連絡先 ===
    setVal(find('#EventDateTotalCapacity', '[name="data[EventDate][total_capacity]"]'), cap);
    setVal(find('#EventPlace',             '[name="data[Event][place]"]'),              place);
    if (zoomUrl) setVal(find('#EventPlaceUrl', '[name="data[Event][place_url]"]'), zoomUrl);
    const countryEl = find('[name="data[Event][country]"]');
    if (countryEl) setSelectOpt(countryEl, 'JPN');
    setVal(find('#EventTel',   '[name="data[Event][tel]"]'),   tel);
    setVal(find('#EventEmail', '[name="data[Event][email]"]'), email);

    // === 入力後の値確認 ===
    const checks = [
      ['description', '#EventDescription, [name="data[Event][description]"]'],
      ['start_date',  '[name="data[EventDate][start_date_date]"]'],
      ['end_date',    '[name="data[EventDate][end_date_date]"]'],
      ['entry_start', '[name="data[EventDate][entry_start_date_date]"]'],
      ['entry_end',   '[name="data[EventDate][entry_end_date_date]"]'],
    ];
    const verifyLines = checks.map(([label, sel]) => {
      const el = document.querySelector(sel);
      return `${label}="${el ? el.value.slice(0, 30) : 'NOT_FOUND'}"`;
    });
    logs.push(`検証: ${verifyLines.join(' | ')}`);

    return logs;
  }, { title, summary80, ymdDash, ymdEndDash, entry7, entry1, tStart, tEnd, cap, place, zoomUrl: ef.zoomUrl || '', tel, email: cfg.email });

  for (const l of fillResult) log(`[こくチーズ] ${l}`);

  // ===== 7. サブジャンル（ジャンル選択後に非同期更新の可能性） =====
  await page.waitForTimeout(600);
  await page.evaluate(() => {
    const sel = document.querySelector('#EventGenreSub, [name="data[Event][genre_sub]"]');
    if (sel && sel.tagName === 'SELECT') {
      const opt = [...sel.options].find(o => o.value && o.value !== '' && o.value !== '0');
      if (opt) { sel.value = opt.value; sel.dispatchEvent(new Event('change', { bubbles: true })); }
    }
  }).catch(() => {});

  // ===== 8. 送信前FormData確認 =====
  await page.waitForTimeout(300);
  const preSubmit = await page.evaluate(() => {
    const form = [...document.querySelectorAll('form')].find(f =>
      f.querySelector('[name="data[EventDate][start_date_date]"]') ||
      f.querySelector('[name="data[Event][description]"]')
    );
    if (!form) return { error: 'FORM_NOT_FOUND' };
    const fd = new FormData(form);
    const obj = {};
    for (const [k, v] of fd.entries()) {
      if (typeof v === 'string' && v.length < 200 && !k.includes('photo')) obj[k] = v;
    }
    return obj;
  });

  if (preSubmit.error) {
    log(`[こくチーズ] ⚠️ ${preSubmit.error} — フォームが見つからない可能性`);
  } else {
    const checkKeys = [
      'data[Event][description]',
      'data[EventDate][start_date_date]', 'data[EventDate][end_date_date]',
      'data[EventDate][entry_start_date_date]', 'data[EventDate][entry_end_date_date]',
    ];
    const summary_check = checkKeys.map(k => {
      const v = preSubmit[k];
      return `${k.split('][').pop().replace(']','')}:${v !== undefined ? (v || '❌空') : '❌未存在'}`;
    }).join(' | ');
    log(`[こくチーズ] ★FormData確認: ${summary_check}`);

    // デバッグ用にJSONで保存
    try {
      writeFileSync(join(__dirname, 'kokuchpro-pre-submit.json'), JSON.stringify(preSubmit, null, 2), 'utf-8');
    } catch (_) {}
  }

  // ===== 8.5. 画像アップロード =====
  if (eventFields.imagePath) {
    log(`[こくチーズ] 📸 画像アップロード中...`);
    try {
      const fileInputs = page.locator('input[type="file"]');
      const count = await fileInputs.count();
      if (count > 0) {
        await fileInputs.first().setInputFiles(eventFields.imagePath);
        await page.waitForTimeout(1000);
        log(`[こくチーズ] ✅ 画像アップロード完了`);
      } else {
        log(`[こくチーズ] ⚠️ 画像アップロードフィールドが見つかりません`);
      }
    } catch (e) {
      log(`[こくチーズ] ⚠️ 画像アップロード失敗: ${e.message}`);
    }
  }

  // ===== 9. 送信 =====
  let capturedPost = null;
  const captureRequest = (req) => {
    if (req.method() === 'POST') {
      try {
        const postData = req.postData() || '';
        capturedPost = {};
        if (postData.startsWith('--')) {
          const boundary = postData.slice(2).split(/\r?\n/)[0].trim();
          const parts = postData.split(new RegExp(`--${boundary.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`));
          for (const p of parts.slice(1, -1)) {
            const nm = p.match(/name="([^"]+)"/);
            const vl = p.match(/\r?\n\r?\n([\s\S]*?)(?=\r?\n--|$)/);
            if (nm && !p.includes('filename=')) {
              const key = nm[1];
              if (!key.includes('photo')) capturedPost[key] = (vl ? vl[1].trim() : '').slice(0, 200);
            }
          }
        } else if (postData) {
          for (const [k, v] of new URLSearchParams(postData)) capturedPost[k] = v;
        }
      } catch (_) {}
    }
  };
  page.on('request', captureRequest);

  // ===== 日次制限チェック =====
  // HTML全体のテキストから制限メッセージを検出（セレクターに依存しない）
  const pageText = await page.evaluate(() => document.documentElement.textContent || '');
  if (pageText.includes('登録数が制限') || pageText.includes('1日最大') || pageText.includes('明日以降にイベント')) {
    throw new Error('日次制限エラー: こくちーずの1日3件制限に達しました。明日以降にお試しください（プレミアム会員は20件/日）');
  }

  // ===== 送信ボタンクリック =====
  // 「イベントを登録する」ボタンを探す（戻るボタン等を除外）
  const regBtnInfo = await page.evaluate(() => {
    // input[type=submit] から登録系のボタンを探す
    const submits = [...document.querySelectorAll('input[type="submit"]')];
    const reg = submits.find(b => {
      const v = b.value || '';
      return !v.includes('選び直す') && !v.includes('戻る') && !v.includes('キャンセル') && !v.includes('検索');
    });
    if (reg) return { tag: 'INPUT', value: reg.value, selector: `input[type="submit"][value="${reg.value}"]` };

    // button[type=submit]（ページ上部の検索フォーム以外）
    const btns = [...document.querySelectorAll('button[type="submit"]')];
    const regBtn = btns.find(b => {
      const form = b.closest('form');
      return form && form.querySelector('[name="data[EventDate][start_date_date]"]');
    });
    if (regBtn) return { tag: 'BUTTON', value: regBtn.textContent?.trim() || '', selector: null };

    return { tag: null, value: null, selector: null };
  });
  log(`[こくチーズ] 登録ボタン検索: ${JSON.stringify(regBtnInfo)}`);

  if (!regBtnInfo.tag) {
    throw new Error('送信ボタンが見つかりません（日次制限以外の原因の可能性があります）');
  }

  let submitBtn;
  if (regBtnInfo.selector) {
    submitBtn = page.locator(regBtnInfo.selector).first();
  } else {
    // button[type="submit"] でeventFormの中
    const eventForm = page.locator('form').filter({
      has: page.locator('[name="data[EventDate][start_date_date]"]'),
    });
    submitBtn = eventForm.locator('button[type="submit"]').first();
  }

  await submitBtn.scrollIntoViewIfNeeded().catch(() => {});
  log(`[こくチーズ] 送信: クリック "${regBtnInfo.value}"`);
  await Promise.all([
    page.waitForNavigation({ timeout: 30000 }).catch(() => {}),
    submitBtn.click(),
  ]);
  page.off('request', captureRequest);

  // ===== 10. 結果確認 =====
  if (page.url().includes('/regist/')) {
    // 実際に送信された値をログ
    if (capturedPost && Object.keys(capturedPost).length > 0) {
      const problemKeys = [
        'data[Event][description]',
        'data[EventDate][start_date_date]', 'data[EventDate][end_date_date]',
        'data[EventDate][entry_start_date_date]', 'data[EventDate][entry_end_date_date]',
      ];
      const sentLines = problemKeys.map(k => {
        const v = capturedPost[k];
        return `  ${(v === '' || v === undefined) ? '❌空' : '✓'} ${k}="${String(v ?? '').slice(0, 50)}"`;
      });
      log(`[こくチーズ] ★実際に送信された値:\n${sentLines.join('\n')}`);
      const dateRelatedKeys = Object.keys(capturedPost).filter(k => k.toLowerCase().includes('date') || k.toLowerCase().includes('time'));
      log(`[こくチーズ] ★日付/時刻関連キー: ${dateRelatedKeys.join(', ')}`);
      try {
        writeFileSync(join(__dirname, 'kokuchpro-post-debug.json'), JSON.stringify(capturedPost, null, 2), 'utf-8');
        log(`[こくチーズ] ★デバッグJSON保存: kokuchpro-post-debug.json`);
      } catch (_) {}
    } else {
      log(`[こくチーズ] ★capturedPost: null（リクエストキャプチャ失敗）`);
    }

    const errors = await page.evaluate(() =>
      [...document.querySelectorAll('.error-message, [class*="error"], .alert, .alert-error')]
        .map(el => el.textContent.trim()).filter(Boolean).join(' / ')
    );
    throw new Error(`登録失敗（バリデーションエラー）: ${errors || '不明'}`);
  }

  log(`[こくチーズ] ✅ 投稿完了 → ${page.url()}`);
}
