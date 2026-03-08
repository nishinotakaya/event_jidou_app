import inquirer from 'inquirer';
import { readFile, writeFile } from 'fs/promises';
import { existsSync } from 'fs';

const FILES = {
  event: './texts/event.json',
  student: './texts/student.json',
};

const TYPE_LABELS = {
  event: 'イベント告知',
  student: '受講生サポート',
};

// ===== ファイル読み書き =====
async function load(type) {
  const path = FILES[type];
  if (!existsSync(path)) return [];
  const raw = await readFile(path, 'utf-8');
  return JSON.parse(raw);
}

async function save(type, data) {
  await writeFile(FILES[type], JSON.stringify(data, null, 2), 'utf-8');
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function nextId(data, type) {
  const prefix = type === 'event' ? 'event_' : 'student_';
  const nums = data
    .map((d) => parseInt(d.id.replace(prefix, ''), 10))
    .filter((n) => !isNaN(n));
  const max = nums.length > 0 ? Math.max(...nums) : 0;
  return `${prefix}${String(max + 1).padStart(3, '0')}`;
}

// ===== 一覧表示 =====
async function listTexts() {
  const { type } = await inquirer.prompt([
    {
      type: 'list',
      name: 'type',
      message: '種別を選択:',
      choices: [
        { name: 'イベント告知', value: 'event' },
        { name: '受講生サポート', value: 'student' },
      ],
    },
  ]);

  const data = await load(type);

  if (data.length === 0) {
    console.log('\nテキストがまだありません。\n');
    return;
  }

  console.log(`\n===== テキスト一覧（${TYPE_LABELS[type]}）=====\n`);
  console.log('No. | ID          | 名前                   | 更新日時');
  console.log('----+-------------+------------------------+----------');
  data.forEach((d, i) => {
    const no = String(i + 1).padStart(3);
    const id = d.id.padEnd(12);
    const name = d.name.padEnd(22);
    console.log(` ${no} | ${id}| ${name}| ${d.updatedAt}`);
  });

  console.log('');

  const { selected } = await inquirer.prompt([
    {
      type: 'list',
      name: 'selected',
      message: '内容を確認するテキストを選択（確認しない場合は「戻る」）:',
      choices: [
        ...data.map((d, i) => ({ name: `${i + 1}. ${d.name}`, value: i })),
        { name: '── 戻る ──', value: -1 },
      ],
    },
  ]);

  if (selected >= 0) {
    const item = data[selected];
    console.log(`\n----- ${item.name} -----`);
    console.log(item.content);
    console.log('----------------------\n');
  }
}

// ===== 作成 =====
async function createText() {
  const { type } = await inquirer.prompt([
    {
      type: 'list',
      name: 'type',
      message: '種別を選択:',
      choices: [
        { name: 'イベント告知', value: 'event' },
        { name: '受講生サポート', value: 'student' },
      ],
    },
  ]);

  const { name, content } = await inquirer.prompt([
    {
      type: 'input',
      name: 'name',
      message: 'テキスト名:',
      validate: (v) => v.trim() !== '' || '名前を入力してください',
    },
    {
      type: 'editor',
      name: 'content',
      message: '内容を入力（エディタが開きます）:',
    },
  ]);

  const data = await load(type);
  const id = nextId(data, type);
  const now = today();

  data.push({ id, name: name.trim(), type, content: content.trim(), createdAt: now, updatedAt: now });
  await save(type, data);

  console.log(`\n✅ 作成しました（ID: ${id}）\n`);
}

// ===== 編集 =====
async function editText() {
  const { type } = await inquirer.prompt([
    {
      type: 'list',
      name: 'type',
      message: '種別を選択:',
      choices: [
        { name: 'イベント告知', value: 'event' },
        { name: '受講生サポート', value: 'student' },
      ],
    },
  ]);

  const data = await load(type);

  if (data.length === 0) {
    console.log('\nテキストがまだありません。\n');
    return;
  }

  const { selected } = await inquirer.prompt([
    {
      type: 'list',
      name: 'selected',
      message: '編集するテキストを選択:',
      choices: data.map((d, i) => ({ name: `${i + 1}. ${d.name}`, value: i })),
    },
  ]);

  const item = data[selected];

  console.log(`\n----- 現在の内容（${item.name}）-----`);
  console.log(item.content);
  console.log('--------------------------------------\n');

  const { newName, newContent } = await inquirer.prompt([
    {
      type: 'input',
      name: 'newName',
      message: '新しい名前（そのままEnterで変更なし）:',
      default: item.name,
    },
    {
      type: 'editor',
      name: 'newContent',
      message: '新しい内容（エディタが開きます）:',
      default: item.content,
    },
  ]);

  data[selected] = {
    ...item,
    name: newName.trim(),
    content: newContent.trim(),
    updatedAt: today(),
  };

  await save(type, data);
  console.log(`\n✅ 編集しました（${newName}）\n`);
}

// ===== 削除 =====
async function deleteText() {
  const { type } = await inquirer.prompt([
    {
      type: 'list',
      name: 'type',
      message: '種別を選択:',
      choices: [
        { name: 'イベント告知', value: 'event' },
        { name: '受講生サポート', value: 'student' },
      ],
    },
  ]);

  const data = await load(type);

  if (data.length === 0) {
    console.log('\nテキストがまだありません。\n');
    return;
  }

  const { selected } = await inquirer.prompt([
    {
      type: 'list',
      name: 'selected',
      message: '削除するテキストを選択:',
      choices: data.map((d, i) => ({ name: `${i + 1}. ${d.name}`, value: i })),
    },
  ]);

  const item = data[selected];

  console.log(`\n以下を削除します:`);
  console.log(`名前: ${item.name}`);
  console.log(`内容: ${item.content.slice(0, 50)}...\n`);

  data.splice(selected, 1);
  await save(type, data);
  console.log(`✅ 削除しました（${item.name}）\n`);
}

// ===== メインメニュー =====
async function main() {
  console.log('\n📋 テキスト管理アプリ\n');

  while (true) {
    const { action } = await inquirer.prompt([
      {
        type: 'list',
        name: 'action',
        message: 'メニューを選択:',
        choices: [
          { name: '1. 一覧を見る', value: 'list' },
          { name: '2. テキストを作成する', value: 'create' },
          { name: '3. テキストを編集する', value: 'edit' },
          { name: '4. テキストを削除する', value: 'delete' },
          { name: '0. 終了', value: 'exit' },
        ],
      },
    ]);

    if (action === 'exit') {
      console.log('\n終了します。\n');
      break;
    }

    if (action === 'list') await listTexts();
    if (action === 'create') await createText();
    if (action === 'edit') await editText();
    if (action === 'delete') await deleteText();
  }
}

main();
