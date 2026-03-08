import { chromium } from 'playwright';
import inquirer from 'inquirer';
import dotenv from 'dotenv';
dotenv.config();

// ===== イベント情報の入力 =====
async function askEventInfo() {
  return inquirer.prompt([
    {
      type: 'input',
      name: 'title',
      message: 'イベントタイトル:',
      default: '【10分で?!】AIで最強の業務効率化アプリ作成会！',
    },
    {
      type: 'input',
      name: 'date',
      message: '開催日時（例: 2026年3月25日（水）20:30〜21:30）:',
      default: '2026年3月25日（水）20:30〜21:30',
    },
    {
      type: 'input',
      name: 'format',
      message: '開催形式:',
      default: 'オンライン（Zoom）',
    },
    {
      type: 'input',
      name: 'description',
      message: 'セミナー内容（簡潔に）:',
      default: 'Google Antigravityを使ったAI業務効率化アプリ入門セミナー',
    },
    {
      type: 'checkbox',
      name: 'targets',
      message: '投稿先を選択（スペースでチェック）:',
      choices: ['こくチーズ', 'Peatix', 'connpass', 'techplay'],
      default: ['こくチーズ', 'Peatix', 'connpass', 'techplay'],
    },
  ]);
}

// ===== 共通の告知文を生成 =====
function buildPlainText(info) {
  return `${info.title}

■ 開催日時
${info.date}
※ 開始5分前から入室可能 / 途中参加・退出OK

■ 開催形式
${info.format}
参加URLは登録後にメールでお送りします

■ 参加費
無料

■ セミナー内容
${info.description}
専門知識・事前準備は不要です。

■ このセミナーで得られること
✅ AI業務効率化アプリが作れるようになる（初心者でも10分で実践可能）
✅ 仕事に役立つAI活用のアイデアが見つかる
✅ 最新AIツール「Google Antigravity」を深く理解できる
✅ 講師への質問・相談ができる（質疑応答あり）

■ 参加スタイル
・カメラ・マイクOFFで参加OK
・発言・質問は任意
・途中参加・途中退出OK

■ 注意事項
・録画・録音・画面キャプチャはご遠慮ください
・接続トラブル時は再入室してください

気軽にご参加ください。お会いできるのを楽しみにしています！`;
}

function buildMarkdown(info) {
  return `## 開催概要

${info.description}

初心者でも **10分で実践的なAIアプリが作れる** 入門セミナーです。

## 日時・形式

- **日時**: ${info.date}
- **形式**: ${info.format}
- **参加費**: 無料
- ※ 開始5分前から入室可能 / 途中参加・退出OK

## このセミナーで得られること

- ✅ AI業務効率化アプリが作れるようになる
- ✅ 仕事に役立つAI活用のアイデアが見つかる
- ✅ 最新AIツール「Google Antigravity」を深く理解できる
- ✅ 講師への質問・相談ができる（質疑応答あり）

## 参加スタイル

- カメラ・マイクOFFで参加OK / 発言・質問は任意
- 途中参加・途中退出OK

## 注意事項

- 録画・録音・画面キャプチャはご遠慮ください
- 接続トラブル時は再入室してください

気軽にご参加ください。お会いできるのを楽しみにしています！`;
}

// ===== 各サイトへの投稿 =====

async function postToKokuch(page, info) {
  const text = buildPlainText(info);
  await page.goto('https://www.kokuchpro.com/account/login/');
  await page.fill('input[name="email"]', process.env.KOKUCH_EMAIL);
  await page.fill('input[name="password"]', process.env.KOKUCH_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();

  await page.goto('https://www.kokuchpro.com/event/create/');
  await page.fill('input[name="name"]', info.title);
  await page.fill('textarea[name="body"]', text);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();
}

async function postToPeatix(page, info) {
  const text = buildPlainText(info);
  await page.goto('https://peatix.com/signin');
  await page.fill('input[name="email"]', process.env.PEATIX_EMAIL);
  await page.fill('input[name="password"]', process.env.PEATIX_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();

  await page.goto('https://peatix.com/group/16510066/event/create');
  await page.fill('input[name="name"]', info.title);

  // リッチテキストエリアへの入力
  const bodyFrame = page.frameLocator('iframe').first();
  await bodyFrame.locator('body').fill(text);

  await page.click('button[type="submit"]');
  await page.waitForNavigation();
}

async function postToConnpass(page, info) {
  const text = buildMarkdown(info);
  await page.goto('https://connpass.com/login/');
  await page.fill('input[name="username"]', process.env.CONNPASS_EMAIL);
  await page.fill('input[name="password"]', process.env.CONNPASS_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();

  await page.goto('https://connpass.com/event/create/');
  await page.fill('input[name="title"]', info.title);
  await page.fill('textarea[name="catch"]', info.description);
  await page.fill('textarea[name="description"]', text);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();
}

async function postToTechplay(page, info) {
  const text = buildPlainText(info);
  await page.goto('https://techplay.jp/signin');
  await page.fill('input[name="email"]', process.env.TECHPLAY_EMAIL);
  await page.fill('input[name="password"]', process.env.TECHPLAY_PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();

  await page.goto('https://techplay.jp/event/991816/edit');
  await page.fill('input[name="title"]', info.title);
  await page.fill('textarea[name="description"]', text);
  await page.click('button[type="submit"]');
  await page.waitForNavigation();
}

// ===== メイン =====
const SITE_HANDLERS = {
  'こくチーズ': postToKokuch,
  'Peatix': postToPeatix,
  'connpass': postToConnpass,
  'techplay': postToTechplay,
};

async function main() {
  console.log('\n📣 イベント告知自動投稿アプリ\n');

  const info = await askEventInfo();

  if (info.targets.length === 0) {
    console.log('投稿先が選択されていません。終了します。');
    return;
  }

  const browser = await chromium.launch({ headless: false });
  const results = [];

  for (const site of info.targets) {
    const page = await browser.newPage();
    try {
      console.log(`\n[${site}] 投稿中...`);
      await SITE_HANDLERS[site](page, info);
      results.push({ site, status: '✅ 投稿完了' });
      console.log(`[${site}] ✅ 完了`);
    } catch (err) {
      results.push({ site, status: `❌ 失敗: ${err.message}` });
      console.error(`[${site}] ❌ 失敗:`, err.message);
    } finally {
      await page.close();
    }
  }

  await browser.close();

  console.log('\n===== 投稿結果 =====');
  for (const r of results) {
    console.log(`[${r.site}] ${r.status}`);
  }
}

main();
