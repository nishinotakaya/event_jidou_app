import { createConsumer } from '@rails/actioncable';

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

// ===== Zoom Settings =====
export async function fetchZoomSettings() {
  const res = await fetch('/api/zoom_settings');
  if (!res.ok) throw new Error('Zoom設定の取得に失敗しました');
  return res.json();
}

export async function saveZoomSetting({ label, title, zoomUrl, meetingId, passcode }) {
  const res = await fetch('/api/zoom_settings', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ label, title, zoom_url: zoomUrl, meeting_id: meetingId, passcode }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'Zoom設定の保存に失敗しました');
  }
  return res.json();
}

export async function updateZoomSetting(id, { label, zoomUrl, meetingId, passcode }) {
  const res = await fetch(`/api/zoom_settings/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ label, zoom_url: zoomUrl, meeting_id: meetingId, passcode }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'Zoom設定の更新に失敗しました');
  }
  return res.json();
}

export async function deleteZoomSetting(id) {
  const res = await fetch(`/api/zoom_settings/${id}`, { method: 'DELETE' });
  if (!res.ok) throw new Error('Zoom設定の削除に失敗しました');
  return res.json();
}

export async function createZoomMeeting({ title, startDate, startTime, duration }, onEvent) {
  const res = await fetch('/api/zoom/create_meeting', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, startDate, startTime, duration }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(text || 'Zoomミーティング作成に失敗しました');
  }
  const { job_id } = await res.json();

  const cableUrl = import.meta.env.VITE_CABLE_URL || '/cable';
  const { createConsumer } = await import('@rails/actioncable');
  const consumer = createConsumer(cableUrl);

  return new Promise((resolve, reject) => {
    const subscription = consumer.subscriptions.create(
      { channel: 'PostChannel', job_id },
      {
        received(data) {
          onEvent(data);
          if (data.type === 'done') {
            subscription.unsubscribe();
            consumer.disconnect();
            resolve();
          } else if (data.type === 'error') {
            // error の後に done が来るので done で解決する
          }
        },
        rejected() {
          consumer.disconnect();
          reject(new Error('ActionCable接続が拒否されました'));
        },
      }
    );
  });
}

// ===== App Settings (DB-backed KVS) =====
export async function fetchAppSettings(keys) {
  const query = keys ? `?keys=${keys.join(',')}` : '';
  const res = await fetch(`/api/app_settings${query}`);
  if (!res.ok) throw new Error('設定の取得に失敗しました');
  return res.json();
}

export async function saveAppSettings(pairs) {
  const res = await fetch('/api/app_settings', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(pairs),
  });
  if (!res.ok) throw new Error('設定の保存に失敗しました');
  return res.json();
}

// ===== Service Connections =====
export async function fetchServiceConnections() {
  const res = await fetch('/api/service_connections');
  if (!res.ok) throw new Error('接続情報の取得に失敗しました');
  return res.json();
}

export async function saveServiceConnection({ serviceName, email, password }) {
  const res = await fetch('/api/service_connections', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ service_name: serviceName, email, password }),
  });
  if (!res.ok) throw new Error('接続情報の保存に失敗しました');
  return res.json();
}

export async function updateServiceConnection(id, { email, password }) {
  const res = await fetch(`/api/service_connections/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error('接続情報の更新に失敗しました');
  return res.json();
}

export async function deleteServiceConnection(id) {
  const res = await fetch(`/api/service_connections/${id}`, { method: 'DELETE' });
  if (!res.ok) throw new Error('接続の削除に失敗しました');
  return res.json();
}

export async function testServiceConnection(id) {
  const res = await fetch(`/api/service_connections/${id}/test`, { method: 'POST' });
  if (!res.ok) throw new Error('接続テストの開始に失敗しました');
  return res.json();
}

export async function testNewServiceConnection({ serviceName, email, password }) {
  const res = await fetch('/api/service_connections/test_new', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ service_name: serviceName, email, password }),
  });
  if (!res.ok) throw new Error('接続テストの開始に失敗しました');
  return res.json();
}

export async function migrateFromEnv() {
  const res = await fetch('/api/service_connections/migrate_from_env', { method: 'POST' });
  if (!res.ok) throw new Error('ENV移行に失敗しました');
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

export async function aiGenerate({ title, type, apiKey, eventDate, eventTime, eventEndTime, eventSubType, zoomUrl, meetingId, passcode }) {
  const res = await fetch('/api/ai/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, type, apiKey, eventDate, eventTime, eventEndTime, eventSubType, zoomUrl, meetingId, passcode }),
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

// ===== Post (ActionCable) =====
// Returns { jobId, subscription } — caller must call subscription.unsubscribe() when done
export async function postToSites({ content, sites, eventFields, generateImage, imageStyle, openaiApiKey }, onEvent) {
  // 1. Enqueue job on Rails backend → get job_id
  const res = await fetch('/api/post', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content, sites, eventFields, generateImage, imageStyle, openaiApiKey }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(text || '投稿に失敗しました');
  }
  const { job_id } = await res.json();

  // 2. Subscribe to ActionCable PostChannel for real-time progress
  const cableUrl = import.meta.env.VITE_CABLE_URL || '/cable';
  const consumer = createConsumer(cableUrl);

  return new Promise((resolve, reject) => {
    const subscription = consumer.subscriptions.create(
      { channel: 'PostChannel', job_id },
      {
        received(data) {
          onEvent(data);
          if (data.type === 'done' || data.type === 'error') {
            subscription.unsubscribe();
            consumer.disconnect();
            if (data.type === 'error') reject(new Error(data.message || '投稿エラー'));
            else resolve();
          }
        },
        rejected() {
          consumer.disconnect();
          reject(new Error('ActionCable接続が拒否されました'));
        },
      }
    );
  });
}
