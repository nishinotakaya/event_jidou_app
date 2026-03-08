import { chromium } from 'playwright';
import inquirer from 'inquirer';
import dotenv from 'dotenv';
dotenv.config();

// ===== メッセージテンプレート =====
const MESSAGES = {
  '未提出フォロー': (name) =>
    `${name}さん、こんにちは！\n課題がまだ届いていないのですが、進捗いかがですか？\nもし詰まっているところがあれば気軽に教えてください😊`,

  '学習停滞フォロー': (name) =>
    `${name}さん、最近どうですか？\nしばらくログインが確認できていないのが気になって連絡しました。\n忙しいですか？それとも何か詰まっていますか？`,

  '提出確認': (name) =>
    `${name}さん、提出ありがとうございます！\n内容確認しました。フィードバックをお送りします。`,

  '面談前案内': (name, extra) =>
    `${name}さん、${extra.datetime}の面談よろしくお願いします。\n当日は${extra.agenda}についてお話しする予定です。\n事前に確認しておきたいことがあればぜひ教えてください。`,

  '面談後フォロー': (name, extra) =>
    `${name}さん、今日はお時間ありがとうございました！\n次のステップは「${extra.nextAction}」です。\n何か不明点があればいつでも聞いてください。`,
};

// ===== 入力プロンプト =====
async function askSupportInfo() {
  const base = await inquirer.prompt([
    {
      type: 'input',
      name: 'studentName',
      message: '受講生の名前（例: 田中さん）:',
    },
    {
      type: 'list',
      name: 'pattern',
      message: '送信パターンを選択:',
      choices: Object.keys(MESSAGES),
    },
  ]);

  let extra = {};

  if (base.pattern === '面談前案内') {
    const ans = await inquirer.prompt([
      { type: 'input', name: 'datetime', message: '面談日時（例: 3月25日 20:30）:' },
      { type: 'input', name: 'agenda', message: '面談アジェンダ（例: 課題の振り返り）:' },
    ]);
    extra = ans;
  }

  if (base.pattern === '面談後フォロー') {
    const ans = await inquirer.prompt([
      { type: 'input', name: 'nextAction', message: '次のアクション（例: 第3章を進める）:' },
    ]);
    extra = ans;
  }

  return { ...base, extra };
}

// ===== e-running へのメッセージ送信 =====
async function sendMessage(page, studentName, message) {
  const baseUrl = process.env.ERUNNING_URL;

  // ログイン
  await page.goto(`${baseUrl}/login`);
  await page.fill('input[name="email"]', process.env.ERUNNING_EMAIL);
  await page.fill('input[name="password"]', process.env.ERUNNING_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();

  // 受講生一覧から対象者を検索
  await page.goto(`${baseUrl}/students`);
  await page.fill('input[placeholder*="検索"], input[name="search"]', studentName);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1000);

  // 対象受講生のリンクをクリック
  await page.click(`text=${studentName}`);
  await page.waitForNavigation();

  // メッセージ送信フォームに入力
  await page.fill('textarea[name="message"], textarea[placeholder*="メッセージ"]', message);
  await page.click('button[type="submit"], button:has-text("送信")');
  await page.waitForTimeout(1000);
}

// ===== メイン =====
async function main() {
  console.log('\n📚 受講生サポート自動送信アプリ\n');

  if (!process.env.ERUNNING_URL) {
    console.error('❌ .env に ERUNNING_URL が設定されていません。');
    process.exit(1);
  }

  const { studentName, pattern, extra } = await askSupportInfo();

  const message = MESSAGES[pattern](studentName, extra);

  console.log('\n===== 送信メッセージ確認 =====');
  console.log(message);
  console.log('==============================\n');

  const { confirmed } = await inquirer.prompt([
    {
      type: 'confirm',
      name: 'confirmed',
      message: 'このメッセージを送信しますか？',
      default: true,
    },
  ]);

  if (!confirmed) {
    console.log('送信をキャンセルしました。');
    return;
  }

  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();

  try {
    console.log(`\n[${studentName} / ${pattern}] 送信中...`);
    await sendMessage(page, studentName, message);
    console.log(`[${studentName} / ${pattern}] ✅ 送信完了`);
  } catch (err) {
    console.error(`[${studentName} / ${pattern}] ❌ 失敗:`, err.message);
  } finally {
    await browser.close();
  }
}

main();
