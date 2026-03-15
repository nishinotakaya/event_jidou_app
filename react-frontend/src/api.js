// ===== Texts CRUD =====
export async function fetchTexts(type) {
  const res = await fetch(`/api/texts/${type}`);
  if (!res.ok) throw new Error('テキストの取得に失敗しました');
  return res.json();
}

export async function createText(type, { name, content, folder = '' }) {
  const res = await fetch(`/api/texts/${type}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, content, folder }),
  });
  if (!res.ok) throw new Error('テキストの作成に失敗しました');
  return res.json();
}

export async function updateText(type, id, { name, content, folder }) {
  const res = await fetch(`/api/texts/${type}/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, content, folder }),
  });
  if (!res.ok) throw new Error('テキストの更新に失敗しました');
  return res.json();
}

export async function deleteText(type, id) {
  const res = await fetch(`/api/texts/${type}/${id}`, { method: 'DELETE' });
  if (!res.ok) throw new Error('テキストの削除に失敗しました');
  return res.json();
}

// ===== Folders =====
export async function fetchFolders(type) {
  const res = await fetch(`/api/folders/${type}`);
  if (!res.ok) throw new Error('フォルダの取得に失敗しました');
  return res.json();
}

export async function createFolder(type, { name, parent }) {
  const res = await fetch(`/api/folders/${type}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, parent }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'フォルダの作成に失敗しました');
  }
  return res.json();
}

export async function renameFolder(type, { path, newName }) {
  const res = await fetch(`/api/folders/${type}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path, newName }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'フォルダのリネームに失敗しました');
  }
  return res.json();
}

export async function deleteFolder(type, path) {
  const res = await fetch(`/api/folders/${type}?path=${encodeURIComponent(path)}`, {
    method: 'DELETE',
  });
  if (!res.ok) throw new Error('フォルダの削除に失敗しました');
  return res.json();
}

// ===== AI =====
export async function aiCorrect({ text, apiKey }) {
  const res = await fetch('/api/ai/correct', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, apiKey }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || '校正に失敗しました');
  return data;
}

export async function aiGenerate({ title, type, apiKey, eventDate, eventTime, eventEndTime, eventSubType }) {
  const res = await fetch('/api/ai/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, type, apiKey, eventDate, eventTime, eventEndTime, eventSubType }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || '生成に失敗しました');
  return data;
}

export async function aiAlignDatetime({ text, eventDate, eventTime, eventEndTime, apiKey }) {
  const res = await fetch('/api/ai/align-datetime', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, eventDate, eventTime, eventEndTime, apiKey }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || '日時調整に失敗しました');
  return data;
}

export async function aiAgent({ text, prompt, apiKey }) {
  const res = await fetch('/api/ai/agent', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, prompt, apiKey }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || '処理に失敗しました');
  return data;
}

// ===== Post (SSE streaming via fetch) =====
export async function postToSites({ content, sites, eventFields, generateImage, imageStyle, openaiApiKey }, onEvent) {
  const res = await fetch('/api/post', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content, sites, eventFields, generateImage, imageStyle, openaiApiKey }),
  });

  if (!res.ok || !res.body) {
    const text = await res.text().catch(() => '');
    throw new Error(text || '投稿に失敗しました');
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        try {
          const parsed = JSON.parse(line.slice(6));
          onEvent(parsed);
        } catch {
          // ignore parse errors
        }
      }
    }
  }
}
