let currentType = 'event';
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
  aiGenerate: async (title, type, apiKey) => {
    const r = await fetch('/api/ai/generate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title, type, apiKey }) });
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

// ===== 一覧描画 =====
async function renderList() {
  const data = await api.getAll(currentType);
  list.innerHTML = '';

  if (data.length === 0) {
    emptyMsg.hidden = false;
    return;
  }
  emptyMsg.hidden = true;

  data.forEach((item) => {
    const li = document.createElement('li');
    li.className = 'text-card';

    const postBtn = currentType === 'event'
      ? `<button class="btn btn-icon post" data-id="${item.id}" title="投稿">📣</button>`
      : '';

    li.innerHTML = `
      <div class="card-body">
        <div class="card-name">${esc(item.name)}</div>
        <div class="card-preview">${esc(item.content)}</div>
        <div class="card-meta">更新日: ${item.updatedAt}</div>
      </div>
      <div class="card-actions">
        ${postBtn}
        <button class="btn btn-icon edit" data-id="${item.id}" title="編集">✏️</button>
        <button class="btn btn-icon delete" data-id="${item.id}" data-name="${esc(item.name)}" title="削除">🗑️</button>
      </div>
    `;
    list.appendChild(li);
  });

  // 投稿ボタン
  list.querySelectorAll('.btn-icon.post').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const data = await api.getAll(currentType);
      const item = data.find((d) => d.id === btn.dataset.id);
      openPostModal(item);
    });
  });

  // 編集ボタン
  list.querySelectorAll('.btn-icon.edit').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const data = await api.getAll(currentType);
      const item = data.find((d) => d.id === btn.dataset.id);
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
const SITES = ['こくチーズ', 'Peatix', 'connpass', 'techplay'];

function openPostModal(item) {
  postingItem = item;
  document.getElementById('post-text-name').textContent = `テキスト: ${item.name}`;
  document.getElementById('field-event-title').value = item.name || '';
  postModal.querySelectorAll('input[type="checkbox"]').forEach((cb) => { cb.checked = true; });
  document.getElementById('post-results').hidden = true;
  document.getElementById('results-list').innerHTML = '';
  document.getElementById('log-area').hidden = true;
  document.getElementById('log-box').textContent = '';
  const runBtn = document.getElementById('btn-post-run');
  runBtn.disabled = false;
  runBtn.textContent = '投稿する →';
  document.getElementById('btn-post-cancel').textContent = 'キャンセル';

  // デフォルト日付を30日後に設定
  const d30 = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  const ymd = d30.toISOString().slice(0, 10);
  document.getElementById('field-start-date').value = ymd;
  document.getElementById('field-end-date').value = ymd;

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
  const checked = [...postModal.querySelectorAll('input[type="checkbox"]:checked')].map((cb) => cb.value);
  if (checked.length === 0) { alert('投稿先を1つ以上選択してください。'); return; }

  const runBtn = document.getElementById('btn-post-run');
  runBtn.disabled = true;
  runBtn.textContent = '投稿中...';

  // 結果エリアを待機状態で初期化
  const resultsList = document.getElementById('results-list');
  resultsList.innerHTML = checked.map((site) => `
    <li class="result-item" data-site="${esc(site)}">
      <span class="result-site">${esc(site)}</span>
      <span class="result-status waiting">─ 待機中</span>
    </li>
  `).join('');
  document.getElementById('post-results').hidden = false;

  // ログエリアを表示
  const logBox = document.getElementById('log-box');
  logBox.textContent = '';
  document.getElementById('log-area').hidden = false;

  const addLog = (msg) => {
    logBox.textContent += msg + '\n';
    logBox.scrollTop = logBox.scrollHeight;
  };

  // fetchでSSEストリームを受信
  try {
    const response = await fetch('/api/post', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: postingItem.content,
        sites: checked,
        eventFields: {
          title:     document.getElementById('field-event-title').value.trim() || postingItem.name,
          startDate: document.getElementById('field-start-date').value,
          startTime: document.getElementById('field-start-time').value || '10:00',
          endDate:   document.getElementById('field-end-date').value,
          endTime:   document.getElementById('field-end-time').value || '12:00',
          place:     document.getElementById('field-place').value || 'オンライン',
          capacity:  document.getElementById('field-capacity').value || '50',
          tel:       document.getElementById('field-tel').value || '03-1234-5678',
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
      buffer = lines.pop(); // 未完結の行を保持

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
    renderList();
  });
});

document.getElementById('btn-new').addEventListener('click', () => openModal('create'));

document.getElementById('btn-save').addEventListener('click', async () => {
  const name = document.getElementById('field-name').value.trim();
  const content = document.getElementById('field-content').value.trim();
  if (!name || !content) return alert('名前と内容を入力してください。');
  if (editingId) {
    await api.update(currentType, editingId, { name, content });
  } else {
    await api.create(currentType, { name, content });
  }
  closeModal();
  renderList();
});

document.getElementById('btn-cancel').addEventListener('click', closeModal);

// ===== OpenAI APIキー：保存・表示切替 =====
document.getElementById('field-openai-key').addEventListener('blur', (e) => {
  const v = e.target.value.trim();
  if (v) localStorage.setItem('openai_api_key', v);
});
// ===== 文章自動生成 =====
document.getElementById('btn-generate').addEventListener('click', async () => {
  const nameInput = document.getElementById('field-name');
  const title = nameInput.value.trim();
  if (!title) { alert('名前（タイトル）を入力してください。'); return; }
  const apiKey = document.getElementById('field-openai-key').value.trim() || localStorage.getItem('openai_api_key');
  if (!apiKey) { alert('OpenAI APIキーを入力してください。'); return; }
  const btn = document.getElementById('btn-generate');
  const textarea = document.getElementById('field-content');
  btn.disabled = true;
  btn.textContent = '生成中...';
  try {
    const res = await api.aiGenerate(title, currentType, apiKey);
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
  if (input.type === 'password') {
    input.type = 'text';
    btn.textContent = '🙈';
  } else {
    input.type = 'password';
    btn.textContent = '👁️';
  }
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
      if (e.results[i].isFinal) {
        textarea.value += e.results[i][0].transcript;
      }
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
  const apiKey = document.getElementById('field-openai-key').value.trim() || localStorage.getItem('openai_api_key');
  if (!apiKey) { alert('OpenAI APIキーを入力してください。'); return; }
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
  const apiKey = document.getElementById('field-openai-key').value.trim() || localStorage.getItem('openai_api_key');
  if (!apiKey) { alert('OpenAI APIキーを入力してください。'); return; }
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
  renderList();
});

modal.addEventListener('click', (e) => { if (e.target === modal) closeModal(); });
deleteModal.addEventListener('click', (e) => { if (e.target === deleteModal) closeDeleteModal(); });
postModal.addEventListener('click', (e) => { if (e.target === postModal) closePostModal(); });

// ===== ユーティリティ =====
function esc(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// ===== 初期表示 =====
renderList();
