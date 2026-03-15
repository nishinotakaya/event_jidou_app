let currentType = 'event';
let currentFolder = null; // null = すべて
let currentPage = 1;
const PAGE_SIZE = 10;
let allItems = [];
let allFolders = [];
let editingId = null;
let deletingId = null;
let postingItem = null;

const list = document.getElementById('text-list');
const emptyMsg = document.getElementById('empty-msg');
const modal = document.getElementById('modal');
const deleteModal = document.getElementById('delete-modal');
const postModal = document.getElementById('post-modal');

// ===== API =====
const api = {
  getAll: (type) => fetch(`/api/texts/${type}`).then((r) => r.json()),
  create: (type, body) =>
    fetch(`/api/texts/${type}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then((r) => r.json()),
  update: (type, id, body) =>
    fetch(`/api/texts/${type}/${id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then((r) => r.json()),
  delete: (type, id) =>
    fetch(`/api/texts/${type}/${id}`, { method: 'DELETE' }).then((r) => r.json()),
  post: (body) =>
    fetch('/api/post', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then((r) => r.json()),
  getFolders: (type) => fetch(`/api/folders/${type}`).then((r) => r.json()),
  createFolder: (type, name, parent = '') =>
    fetch(`/api/folders/${type}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name, parent }) }).then((r) => r.json()),
  deleteFolder: (type, path) =>
    fetch(`/api/folders/${encodeURIComponent(type)}?path=${encodeURIComponent(path)}`, { method: 'DELETE' }).then((r) => r.json()),
  renameFolder: (type, path, newName) =>
    fetch(`/api/folders/${encodeURIComponent(type)}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path, newName }) }).then((r) => r.json()),
  aiCorrect: async (text, apiKey) => {
    const r = await fetch('/api/ai/correct', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text, apiKey }) });
    const ct = r.headers.get('content-type') || '';
    if (!ct.includes('application/json')) {
      const t = await r.text();
      throw new Error(t.startsWith('<') ? `サーバーエラー: APIが応答していません。サーバーを再起動してください。(status: ${r.status})` : t.slice(0, 100));
    }
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || `エラー ${r.status}`);
    return j;
  },
  aiGenerate: async (title, type, apiKey, eventDate, eventTime, eventEndTime) => {
    const r = await fetch('/api/ai/generate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title, type, apiKey, eventDate, eventTime, eventEndTime }) });
    const ct = r.headers.get('content-type') || '';
    if (!ct.includes('application/json')) {
      const t = await r.text();
      throw new Error(t.startsWith('<') ? `サーバーエラー: APIが応答していません。(status: ${r.status})` : t.slice(0, 100));
    }
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || `エラー ${r.status}`);
    return j;
  },
  aiAlignDatetime: async (text, eventDate, eventTime, eventEndTime, apiKey) => {
    const r = await fetch('/api/ai/align-datetime', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text, eventDate, eventTime, eventEndTime, apiKey }) });
    const ct = r.headers.get('content-type') || '';
    if (!ct.includes('application/json')) {
      const t = await r.text();
      throw new Error(t.startsWith('<') ? `サーバーエラー: APIが応答していません。(status: ${r.status})` : t.slice(0, 100));
    }
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || `エラー ${r.status}`);
    return j;
  },
  aiAgent: async (text, prompt, apiKey) => {
    const r = await fetch('/api/ai/agent', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text, prompt, apiKey }) });
    const ct = r.headers.get('content-type') || '';
    if (!ct.includes('application/json')) {
      const t = await r.text();
      throw new Error(t.startsWith('<') ? `サーバーエラー: APIが応答していません。サーバーを再起動してください。(status: ${r.status})` : t.slice(0, 100));
    }
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || `エラー ${r.status}`);
    return j;
  },
};

// ===== 開催日時の localStorage 同期 =====
function syncEventDatetime() {
  const date    = document.getElementById('field-gen-date')?.value;
  const time    = document.getElementById('field-gen-time')?.value;
  const endTime = document.getElementById('field-gen-end-time')?.value;
  if (date)    localStorage.setItem('event_gen_date', date);
  if (time)    localStorage.setItem('event_gen_time', time);
  if (endTime) localStorage.setItem('event_gen_end_time', endTime);
}

// ===== APIキー取得・バリデーション =====
function getApiKey(fieldId = 'field-openai-key') {
  const fromField = document.getElementById(fieldId)?.value.trim() || '';
  const fromStorage = localStorage.getItem('openai_api_key') || '';
  const key = fromField || fromStorage;
  if (!key.startsWith('sk-')) {
    if (fromStorage && !fromStorage.startsWith('sk-')) localStorage.removeItem('openai_api_key');
    return null;
  }
  return key;
}

// ===== フォルダ一覧を描画（サイドバー） =====
function renderFolderList() {
  const container = document.getElementById('folder-list');
  const allCount = allItems.length;
  const allBtn = `<button class="folder-btn${currentFolder === null ? ' active' : ''}" data-folder="__all__">すべて <span class="folder-count">${allCount}</span></button>`;

  const folderBtns = allFolders.map(f => {
    const parentPath = f.name;
    const parentCount = allItems.filter(i => (i.folder || '') === parentPath || (i.folder || '').startsWith(parentPath + '/')).length;
    const isParentActive = currentFolder === parentPath;

    const childBtns = f.children.map(c => {
      const childPath = `${parentPath}/${c}`;
      const childCount = allItems.filter(i => (i.folder || '') === childPath).length;
      const isChildActive = currentFolder === childPath;
      return `<div class="folder-child-item">
        <button class="folder-btn folder-child-btn${isChildActive ? ' active' : ''}" data-folder="${esc(childPath)}">└ ${esc(c)} <span class="folder-count">${childCount}</span></button>
        <button class="folder-edit-btn" data-folder="${esc(childPath)}" data-name="${esc(c)}" title="名前変更">✏</button>
        <button class="folder-delete-btn" data-folder="${esc(childPath)}" title="削除">×</button>
      </div>`;
    }).join('');

    return `<div class="folder-parent-group">
      <div class="folder-item${isParentActive ? ' active' : ''}">
        <button class="folder-btn${isParentActive ? ' active' : ''}" data-folder="${esc(parentPath)}">${esc(f.name)} <span class="folder-count">${parentCount}</span></button>
        <button class="folder-edit-btn" data-folder="${esc(parentPath)}" data-name="${esc(f.name)}" title="名前変更">✏</button>
        <button class="folder-delete-btn" data-folder="${esc(parentPath)}" title="削除">×</button>
      </div>
      ${childBtns}
    </div>`;
  }).join('');

  container.innerHTML = allBtn + folderBtns;

  container.querySelectorAll('.folder-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      currentFolder = btn.dataset.folder === '__all__' ? null : btn.dataset.folder;
      currentPage = 1;
      renderList();
      renderFolderList();
    });
  });

  container.querySelectorAll('.folder-delete-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const path = btn.dataset.folder;
      const isChild = path.includes('/');
      const msg = isChild
        ? `子フォルダ「${path.split('/')[1]}」を削除しますか？\n中のアイテムは親フォルダに移動されます。`
        : `フォルダ「${path}」と配下の子フォルダをすべて削除しますか？\n中のアイテムは未分類に移動されます。`;
      if (!confirm(msg)) return;
      await fetch(`/api/folders/${encodeURIComponent(currentType)}?path=${encodeURIComponent(path)}`, { method: 'DELETE' });
      if (currentFolder === path || (currentFolder || '').startsWith(path + '/')) { currentFolder = null; currentPage = 1; }
      await loadData();
    });
  });

  container.querySelectorAll('.folder-edit-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const path = btn.dataset.folder;
      const currentName = btn.dataset.name;
      const newName = prompt('新しいフォルダ名を入力してください', currentName);
      if (!newName || newName === currentName) return;
      const res = await api.renameFolder(currentType, path, newName.trim());
      if (res.error) { alert(`エラー: ${res.error}`); return; }
      // currentFolderが変更対象ならパスを更新
      if (currentFolder === path) {
        const isChild = path.includes('/');
        currentFolder = isChild ? `${path.split('/')[0]}/${newName.trim()}` : newName.trim();
      } else if (!path.includes('/') && (currentFolder || '').startsWith(path + '/')) {
        currentFolder = newName.trim() + currentFolder.slice(path.length);
      }
      await loadData();
    });
  });

  // 親選択セレクトを更新
  const parentSel = document.getElementById('folder-parent-select');
  if (parentSel) {
    parentSel.innerHTML = '<option value="">トップレベル</option>' +
      allFolders.map(f => `<option value="${esc(f.name)}">${esc(f.name)}</option>`).join('');
  }
}

// ===== モーダルのフォルダ選択肢を更新 =====
function updateFolderSelect(selectedFolder = '') {
  const sel = document.getElementById('field-folder');
  if (!sel) return;
  let html = '<option value="">── 未分類 ──</option>';
  allFolders.forEach(f => {
    html += `<option value="${esc(f.name)}"${f.name === selectedFolder ? ' selected' : ''}>📁 ${esc(f.name)}</option>`;
    f.children.forEach(c => {
      const path = `${f.name}/${c}`;
      html += `<option value="${esc(path)}"${path === selectedFolder ? ' selected' : ''}>　└ ${esc(c)}</option>`;
    });
  });
  sel.innerHTML = html;
}

// ===== データ読み込み =====
async function loadData() {
  [allItems, allFolders] = await Promise.all([
    api.getAll(currentType),
    api.getFolders(currentType),
  ]);
  renderFolderList();
  renderList();
}

// ===== ページネーション描画 =====
function renderPagination(total, page) {
  const totalPages = Math.ceil(total / PAGE_SIZE);
  const container = document.getElementById('pagination');
  if (totalPages <= 1) { container.innerHTML = ''; return; }

  const pages = [];
  for (let i = 1; i <= totalPages; i++) {
    if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) {
      pages.push(i);
    } else if (pages[pages.length - 1] !== '...') {
      pages.push('...');
    }
  }

  container.innerHTML = `
    <button class="page-btn" data-page="${page - 1}" ${page === 1 ? 'disabled' : ''}>← 前</button>
    ${pages.map(p => p === '...'
      ? `<span class="page-ellipsis">...</span>`
      : `<button class="page-btn${p === page ? ' active' : ''}" data-page="${p}">${p}</button>`
    ).join('')}
    <button class="page-btn" data-page="${page + 1}" ${page === totalPages ? 'disabled' : ''}>次 →</button>
  `;

  container.querySelectorAll('.page-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      currentPage = parseInt(btn.dataset.page);
      renderList();
    });
  });
}

// ===== 一覧描画 =====
function renderList() {
  list.innerHTML = '';

  // フォルダフィルタ
  const filtered = currentFolder === null
    ? allItems
    : currentFolder.includes('/')
      ? allItems.filter(i => (i.folder || '') === currentFolder)
      : allItems.filter(i => (i.folder || '') === currentFolder || (i.folder || '').startsWith(currentFolder + '/'));

  if (filtered.length === 0) {
    emptyMsg.hidden = false;
    document.getElementById('pagination').innerHTML = '';
    return;
  }
  emptyMsg.hidden = true;

  // ページネーション
  const total = filtered.length;
  const start = (currentPage - 1) * PAGE_SIZE;
  const paged = filtered.slice(start, start + PAGE_SIZE);

  paged.forEach((item) => {
    const li = document.createElement('li');
    li.className = 'text-card';

    const postBtn = currentType === 'event'
      ? `<button class="btn btn-icon post" data-id="${item.id}" title="投稿">📣</button>`
      : '';

    const folderBadge = item.folder
      ? `<span class="card-folder-badge">📁 ${esc(item.folder)}</span>`
      : '';

    let folderOptions = `<option value="">── 未分類 ──</option>`;
    allFolders.forEach(f => {
      folderOptions += `<option value="${esc(f.name)}"${f.name === (item.folder||'') ? ' selected':''}>📁 ${esc(f.name)}</option>`;
      f.children.forEach(c => {
        const path = `${f.name}/${c}`;
        folderOptions += `<option value="${esc(path)}"${path === (item.folder||'') ? ' selected':''}>　└ ${esc(c)}</option>`;
      });
    });

    li.innerHTML = `
      <div class="card-body">
        <div class="card-name">${esc(item.name)}${folderBadge}</div>
        <div class="card-preview">${esc(item.content)}</div>
        <div class="card-meta">更新日: ${item.updatedAt}</div>
      </div>
      <div class="card-actions">
        ${allFolders.length > 0 ? `<select class="card-folder-select" data-id="${item.id}" title="フォルダへ移動">${folderOptions}</select>` : ''}
        ${postBtn}
        <button class="btn btn-icon edit" data-id="${item.id}" title="編集">✏️</button>
        <button class="btn btn-icon delete" data-id="${item.id}" data-name="${esc(item.name)}" title="削除">🗑️</button>
      </div>
    `;
    list.appendChild(li);
  });

  renderPagination(total, currentPage);

  // フォルダ移動セレクト
  list.querySelectorAll('.card-folder-select').forEach((sel) => {
    sel.addEventListener('change', async () => {
      const id = sel.dataset.id;
      const folder = sel.value;
      const item = allItems.find(d => d.id === id);
      if (!item) return;
      await api.update(currentType, id, { name: item.name, content: item.content, folder });
      await loadData();
    });
  });

  // 投稿ボタン
  list.querySelectorAll('.btn-icon.post').forEach((btn) => {
    btn.addEventListener('click', () => {
      const item = allItems.find((d) => d.id === btn.dataset.id);
      openPostModal(item);
    });
  });

  // 編集ボタン
  list.querySelectorAll('.btn-icon.edit').forEach((btn) => {
    btn.addEventListener('click', () => {
      const item = allItems.find((d) => d.id === btn.dataset.id);
      openModal('edit', item);
    });
  });

  // 削除ボタン
  list.querySelectorAll('.btn-icon.delete').forEach((btn) => {
    btn.addEventListener('click', () => openDeleteModal(btn.dataset.id, btn.dataset.name));
  });
}

// ===== 編集モーダル =====
function openModal(mode, item = null) {
  editingId = mode === 'edit' ? item.id : null;
  document.getElementById('modal-title').textContent = mode === 'edit' ? 'テキストを編集' : 'テキストを作成';
  document.getElementById('field-name').value = item?.name ?? '';
  document.getElementById('field-content').value = item?.content ?? '';
  const keyInput = document.getElementById('field-openai-key');
  keyInput.value = localStorage.getItem('openai_api_key') || '';
  keyInput.type = 'password';
  document.getElementById('btn-toggle-key').textContent = '👁️';

  updateFolderSelect(item?.folder || '');

  const dtRow = document.getElementById('gen-datetime-row');
  if (currentType === 'event') {
    dtRow.hidden = false;
    const savedDate = localStorage.getItem('event_gen_date');
    const d30 = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    document.getElementById('field-gen-date').value = savedDate || d30;
    document.getElementById('field-gen-time').value = localStorage.getItem('event_gen_time') || '10:00';
    document.getElementById('field-gen-end-time').value = localStorage.getItem('event_gen_end_time') || '12:00';
  } else {
    dtRow.hidden = true;
  }

  modal.hidden = false;
  document.getElementById('field-name').focus();
}

function closeModal() {
  modal.hidden = true;
  editingId = null;
}

// ===== 削除モーダル =====
function openDeleteModal(id, name) {
  deletingId = id;
  document.getElementById('delete-msg').textContent = `「${name}」を削除します。この操作は元に戻せません。`;
  deleteModal.hidden = false;
}

function closeDeleteModal() {
  deleteModal.hidden = true;
  deletingId = null;
}

// ===== 投稿モーダル =====
function openPostModal(item) {
  postingItem = item;
  document.getElementById('post-text-name').textContent = `テキスト: ${item.name}`;
  document.getElementById('field-event-title').value = item.name || '';
  postModal.querySelectorAll('.site-checks input[type="checkbox"]').forEach((cb) => { cb.checked = true; });
  document.getElementById('check-generate-image').checked = false;
  const savedKey = getApiKey() || '';
  const postKeyField = document.getElementById('field-post-openai-key');
  if (postKeyField) postKeyField.value = savedKey;
  document.getElementById('post-results').hidden = true;
  document.getElementById('results-list').innerHTML = '';
  document.getElementById('log-area').hidden = true;
  document.getElementById('log-box').textContent = '';
  const runBtn = document.getElementById('btn-post-run');
  runBtn.disabled = false;
  runBtn.textContent = '投稿する →';
  document.getElementById('btn-post-cancel').textContent = 'キャンセル';

  const savedDate = localStorage.getItem('event_gen_date');
  const ymd = savedDate || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  document.getElementById('field-start-date').value = ymd;
  document.getElementById('field-end-date').value = ymd;
  document.getElementById('field-start-time').value = localStorage.getItem('event_gen_time') || '10:00';
  document.getElementById('field-end-time').value = localStorage.getItem('event_gen_end_time') || '12:00';
  document.getElementById('field-peatix-event-id').value = '';

  postModal.hidden = false;
}

function closePostModal() {
  postModal.hidden = true;
  postingItem = null;
}

function setResultStatus(site, statusClass, text) {
  const el = document.querySelector(`.result-item[data-site="${site}"] .result-status`);
  if (el) {
    el.className = `result-status ${statusClass}`;
    el.textContent = text;
  }
}

async function runPost() {
  const checked = [...postModal.querySelectorAll('.site-checks input[type="checkbox"]:checked')].map((cb) => cb.value);
  if (checked.length === 0) { alert('投稿先を1つ以上選択してください。'); return; }

  const runBtn = document.getElementById('btn-post-run');
  runBtn.disabled = true;
  runBtn.textContent = '投稿中...';

  const resultsList = document.getElementById('results-list');
  resultsList.innerHTML = checked.map((site) => `
    <li class="result-item" data-site="${esc(site)}">
      <span class="result-site">${esc(site)}</span>
      <span class="result-status waiting">─ 待機中</span>
    </li>
  `).join('');
  document.getElementById('post-results').hidden = false;

  const logBox = document.getElementById('log-box');
  logBox.textContent = '';
  document.getElementById('log-area').hidden = false;

  const addLog = (msg) => {
    logBox.textContent += msg + '\n';
    logBox.scrollTop = logBox.scrollHeight;
  };

  try {
    const generateImage = document.getElementById('check-generate-image').checked;
    const imageStyle = document.querySelector('input[name="image-style"]:checked')?.value || 'cute';
    const postApiKey = getApiKey('field-post-openai-key') || getApiKey();
    if (generateImage && !postApiKey) {
      alert('画像自動生成にはOpenAI APIキーが必要です。\n画像生成セクションのキー入力欄に入力してください。');
      runBtn.disabled = false;
      runBtn.textContent = '投稿する →';
      return;
    }
    const response = await fetch('/api/post', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: postingItem.content,
        sites: checked,
        generateImage,
        imageStyle,
        openaiApiKey: generateImage ? postApiKey : null,
        eventFields: {
          title:          document.getElementById('field-event-title').value.trim() || postingItem.name,
          startDate:      document.getElementById('field-start-date').value,
          startTime:      document.getElementById('field-start-time').value || '10:00',
          endDate:        document.getElementById('field-end-date').value,
          endTime:        document.getElementById('field-end-time').value || '12:00',
          place:          document.getElementById('field-place').value || 'オンライン',
          zoomUrl:        document.getElementById('field-zoom-url').value.trim(),
          capacity:       document.getElementById('field-capacity').value || '50',
          tel:            document.getElementById('field-tel').value || '03-1234-5678',
          peatixEventId:  document.getElementById('field-peatix-event-id').value.trim(),
          lmeAccount:     document.querySelector('input[name="lme-account"]:checked')?.value || 'taiken',
        },
      }),
    });

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop();

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        try {
          const data = JSON.parse(line.slice(6));
          if (data.type === 'log') {
            addLog(data.message);
          } else if (data.type === 'status') {
            setResultStatus(data.site, data.status, data.status === 'success' ? '✅ 完了' : data.status === 'running' ? '⏳ 処理中...' : `❌ ${data.message}`);
          } else if (data.type === 'done') {
            runBtn.textContent = '完了';
            document.getElementById('btn-post-cancel').textContent = '閉じる';
          } else if (data.type === 'error') {
            addLog('❌ ' + data.message);
          }
        } catch { /* JSON parse失敗は無視 */ }
      }
    }
  } catch (err) {
    addLog('❌ 通信エラー: ' + err.message);
    runBtn.disabled = false;
    runBtn.textContent = '投稿する →';
  }
}

// ===== イベントリスナー =====
document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'));
    tab.classList.add('active');
    currentType = tab.dataset.type;
    currentFolder = null;
    currentPage = 1;
    loadData();
  });
});

document.getElementById('btn-new').addEventListener('click', () => openModal('create'));

// フォルダ追加
document.getElementById('btn-add-folder').addEventListener('click', async () => {
  const input = document.getElementById('folder-input');
  const parentSel = document.getElementById('folder-parent-select');
  const name = input.value.trim();
  const parent = parentSel?.value || '';
  if (!name) return;
  const res = await api.createFolder(currentType, name, parent);
  if (res.error) { alert(res.error === 'already exists' ? 'そのフォルダは既に存在します' : res.error); return; }
  input.value = '';
  await loadData();
});
document.getElementById('folder-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') document.getElementById('btn-add-folder').click();
});

document.getElementById('btn-save').addEventListener('click', async () => {
  const name = document.getElementById('field-name').value.trim();
  let content = document.getElementById('field-content').value.trim();
  const folder = document.getElementById('field-folder')?.value || '';
  if (!name || !content) return alert('名前と内容を入力してください。');

  const eventDate    = document.getElementById('field-gen-date')?.value || '';
  const eventTime    = document.getElementById('field-gen-time')?.value || '';
  const eventEndTime = document.getElementById('field-gen-end-time')?.value || '';
  if (currentType === 'event' && eventDate) {
    const apiKey = getApiKey();
    if (apiKey) {
      const saveBtn = document.getElementById('btn-save');
      saveBtn.disabled = true;
      saveBtn.textContent = '日時を調整中...';
      try {
        const res = await api.aiAlignDatetime(content, eventDate, eventTime, eventEndTime, apiKey);
        if (res.content) content = res.content;
      } catch (e) {
        // 失敗しても保存は続行
      } finally {
        saveBtn.disabled = false;
        saveBtn.textContent = '保存';
      }
    }
  }

  if (editingId) {
    await api.update(currentType, editingId, { name, content, folder });
  } else {
    await api.create(currentType, { name, content, folder });
  }
  closeModal();
  await loadData();
});

document.getElementById('btn-cancel').addEventListener('click', closeModal);

// ===== OpenAI APIキー：保存・表示切替 =====
document.getElementById('field-openai-key').addEventListener('blur', (e) => {
  const v = e.target.value.trim();
  if (v.startsWith('sk-')) localStorage.setItem('openai_api_key', v);
});

document.getElementById('btn-toggle-post-key').addEventListener('click', () => {
  const input = document.getElementById('field-post-openai-key');
  const btn = document.getElementById('btn-toggle-post-key');
  if (input.type === 'password') { input.type = 'text'; btn.textContent = '🙈'; }
  else { input.type = 'password'; btn.textContent = '👁️'; }
});
document.getElementById('field-post-openai-key').addEventListener('blur', (e) => {
  const v = e.target.value.trim();
  if (v.startsWith('sk-')) localStorage.setItem('openai_api_key', v);
});

// ===== 文章自動生成 =====
document.getElementById('btn-generate').addEventListener('click', async () => {
  const nameInput = document.getElementById('field-name');
  const title = nameInput.value.trim();
  if (!title) { alert('名前（タイトル）を入力してください。'); return; }
  const apiKey = getApiKey();
  if (!apiKey) { alert('有効なOpenAI APIキー（sk-...）を入力してください。'); return; }
  const btn = document.getElementById('btn-generate');
  const textarea = document.getElementById('field-content');
  btn.disabled = true;
  btn.textContent = '生成中...';
  const eventDate    = document.getElementById('field-gen-date')?.value || localStorage.getItem('event_gen_date') || '';
  const eventTime    = document.getElementById('field-gen-time')?.value || localStorage.getItem('event_gen_time') || '10:00';
  const eventEndTime = document.getElementById('field-gen-end-time')?.value || localStorage.getItem('event_gen_end_time') || '12:00';
  if (!eventDate) {
    alert('開催日時（文章生成用）の日付を入力してください。');
    btn.disabled = false;
    btn.textContent = '✨ 文章自動生成';
    return;
  }
  try {
    const res = await api.aiGenerate(title, currentType, apiKey, eventDate, eventTime, eventEndTime);
    if (res.error) throw new Error(res.error);
    textarea.value = res.content;
  } catch (err) {
    alert('生成に失敗しました: ' + err.message);
  } finally {
    btn.disabled = false;
    btn.textContent = '✨ 文章自動生成';
  }
});

document.getElementById('btn-toggle-key').addEventListener('click', () => {
  const input = document.getElementById('field-openai-key');
  const btn = document.getElementById('btn-toggle-key');
  if (input.type === 'password') { input.type = 'text'; btn.textContent = '🙈'; }
  else { input.type = 'password'; btn.textContent = '👁️'; }
});

// ===== 音声入力（Web Speech API） =====
let recognition = null;
let isRecording = false;
document.getElementById('btn-voice').addEventListener('click', async () => {
  const btn = document.getElementById('btn-voice');
  const textarea = document.getElementById('field-content');
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    alert('お使いのブラウザは音声入力に対応していません。Chromeをご利用ください。');
    return;
  }
  if (isRecording) {
    recognition.stop();
    isRecording = false;
    btn.classList.remove('recording');
    return;
  }
  recognition = new SpeechRecognition();
  isRecording = true;
  recognition.lang = 'ja-JP';
  recognition.continuous = true;
  recognition.interimResults = true;
  recognition.onresult = (e) => {
    for (let i = e.resultIndex; i < e.results.length; i++) {
      if (e.results[i].isFinal) textarea.value += e.results[i][0].transcript;
    }
  };
  recognition.onend = () => { isRecording = false; btn.classList.remove('recording'); };
  recognition.start();
  btn.classList.add('recording');
});

// ===== 添削 =====
document.getElementById('btn-correct').addEventListener('click', async () => {
  const textarea = document.getElementById('field-content');
  const text = textarea.value.trim();
  if (!text) { alert('添削するテキストを入力してください。'); return; }
  const apiKey = getApiKey();
  if (!apiKey) { alert('有効なOpenAI APIキー（sk-...）を入力してください。'); return; }
  const btn = document.getElementById('btn-correct');
  btn.disabled = true;
  btn.textContent = '添削中...';
  try {
    const res = await api.aiCorrect(text, apiKey);
    if (res.error) throw new Error(res.error);
    textarea.value = res.corrected;
  } catch (err) {
    alert('添削に失敗しました: ' + err.message);
  } finally {
    btn.disabled = false;
    btn.textContent = '✨ 添削';
  }
});

// ===== AIエージェント =====
const agentModal = document.getElementById('agent-modal');
document.getElementById('btn-agent').addEventListener('click', () => {
  document.getElementById('agent-prompt').value = '';
  document.getElementById('agent-response').textContent = '';
  agentModal.hidden = false;
});
document.getElementById('btn-agent-close').addEventListener('click', () => { agentModal.hidden = true; });
document.getElementById('btn-agent-send').addEventListener('click', async () => {
  const prompt = document.getElementById('agent-prompt').value.trim();
  if (!prompt) { alert('指示を入力してください。'); return; }
  const apiKey = getApiKey();
  if (!apiKey) { alert('有効なOpenAI APIキー（sk-...）を入力してください。'); return; }
  const text = document.getElementById('field-content').value;
  const respEl = document.getElementById('agent-response');
  const btn = document.getElementById('btn-agent-send');
  btn.disabled = true;
  respEl.textContent = '処理中...';
  try {
    const res = await api.aiAgent(text, prompt, apiKey);
    if (res.error) throw new Error(res.error);
    respEl.textContent = res.result;
    document.getElementById('field-content').value = res.result;
  } catch (err) {
    respEl.textContent = 'エラー: ' + err.message;
  } finally {
    btn.disabled = false;
  }
});
agentModal.addEventListener('click', (e) => { if (e.target === agentModal) agentModal.hidden = true; });
document.getElementById('btn-delete-cancel').addEventListener('click', closeDeleteModal);
document.getElementById('btn-post-cancel').addEventListener('click', closePostModal);
document.getElementById('btn-post-run').addEventListener('click', runPost);

document.getElementById('btn-delete-ok').addEventListener('click', async () => {
  await api.delete(currentType, deletingId);
  closeDeleteModal();
  await loadData();
});

// ===== 開催日時フィールドの変更を localStorage に保存 =====
['field-gen-date', 'field-gen-time', 'field-gen-end-time'].forEach((id) => {
  document.getElementById(id)?.addEventListener('change', syncEventDatetime);
});
document.getElementById('field-start-date')?.addEventListener('change', (e) => {
  localStorage.setItem('event_gen_date', e.target.value);
  document.getElementById('field-end-date').value = e.target.value;
});
document.getElementById('field-start-time')?.addEventListener('change', (e) => {
  localStorage.setItem('event_gen_time', e.target.value);
});
document.getElementById('field-end-time')?.addEventListener('change', (e) => {
  localStorage.setItem('event_gen_end_time', e.target.value);
});

modal.addEventListener('click', (e) => { if (e.target === modal) closeModal(); });
deleteModal.addEventListener('click', (e) => { if (e.target === deleteModal) closeDeleteModal(); });
postModal.addEventListener('click', (e) => { if (e.target === postModal) closePostModal(); });

// ===== ユーティリティ =====
function esc(str) {
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// ===== 初期表示 =====
loadData();
