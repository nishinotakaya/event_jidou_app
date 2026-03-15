/**
 * LME post() 動作確認スクリプト
 * 実行: node scripts/test-lme-post.js
 */
import 'dotenv/config';
import { chromium } from 'playwright';
import { post } from '../api/lme.js';

const log = (msg) => console.log(msg);

(async () => {
  const browser = await chromium.launch({ headless: false, slowMo: 80 });
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 } });
  const page = await context.newPage();

  try {
    await post(
      page,
      '■開催日時\n2026年4月13日（月） 10:00〜12:00\n\n■開催形式\nオンライン（Zoom）\n\n■参加費\n無料\n\n■内容\nAIでアプリを作ろう会のテスト配信です。',
      { title: 'AIでアプリを作ろう会', startDate: '2026-04-13', startTime: '10:00' },
      log
    );
    console.log('\n✅ テスト完了');
  } catch (e) {
    console.error('\n❌ エラー:', e.message);
    await page.screenshot({ path: '/tmp/lme-test-error.png', fullPage: true }).catch(() => {});
  } finally {
    await browser.close();
  }
})();
