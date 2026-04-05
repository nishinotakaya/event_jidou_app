import { createConsumer } from '@rails/actioncable';

// ===== Texts CRUD =====
export async function fetchTexts(type) {
  const res = await fetch(`/api/texts/${type}`);
  if (!res.ok) throw new Error('テキストの取得に失敗しました');
  return res.json();
}

export async function createText(type, { name, content, folder = '', eventDate, eventTime, eventEndTime, onclassMentions, onclassChannels, studentPostType }) {
  const body = { name, content, folder, eventDate, eventTime, eventEndTime };
  if (onclassMentions) body.onclassMentions = onclassMentions;
  if (onclassChannels) body.onclassChannels = onclassChannels;
  if (studentPostType) body.studentPostType = studentPostType;
  const res = await fetch(`/api/texts/${type}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error('テキストの作成に失敗しました');
  return res.json();
}

export async function updateText(type, id, { name, content, folder, eventDate, eventTime, eventEndTime, onclassMentions, onclassChannels, studentPostType }) {
  const body = { name, content, folder, eventDate, eventTime, eventEndTime };
  if (onclassMentions) body.onclassMentions = onclassMentions;
  if (onclassChannels) body.onclassChannels = onclassChannels;
  if (studentPostType) body.studentPostType = studentPostType;
  const res = await fetch(`/api/texts/${type}/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
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

export async function browserLogin(serviceName) {
  const res = await fetch('/api/service_connections/browser_login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ service_name: serviceName }),
  });
  if (!res.ok) throw new Error('ブラウザログインの開始に失敗しました');
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

// ===== Posting History =====
export async function fetchPostingHistory(itemId) {
  const res = await fetch(`/api/posting_histories/latest?item_id=${encodeURIComponent(itemId)}`);
  if (!res.ok) return [];
  return res.json();
}

export async function checkParticipants(itemId) {
  const res = await fetch(`/api/posting_histories/check_participants?item_id=${encodeURIComponent(itemId)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) return {};
  return res.json();
}

export async function syncPostingHistory(itemId) {
  const res = await fetch(`/api/posting_histories/sync?item_id=${encodeURIComponent(itemId)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) return [];
  return res.json();
}

export async function checkRegistrations(itemId) {
  const res = await fetch(`/api/posting_histories/check_registrations?item_id=${encodeURIComponent(itemId)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) return [];
  return res.json();
}

// ===== Remote Delete / Cancel (ActionCable) =====

export async function deleteRemoteEvents(itemId, onEvent) {
  const res = await fetch(`/api/post/${encodeURIComponent(itemId)}/remote`, { method: 'DELETE' });
  if (!res.ok) throw new Error('リモート削除の開始に失敗しました');
  const { job_id } = await res.json();
  return subscribeToJob(job_id, onEvent);
}

export async function publishAllEvents(itemId, onEvent) {
  const res = await fetch(`/api/post/${encodeURIComponent(itemId)}/publish_all`, { method: 'POST' });
  if (!res.ok) throw new Error('一括公開の開始に失敗しました');
  const { job_id } = await res.json();
  return subscribeToJob(job_id, onEvent);
}

export async function cancelRemoteEvents(itemId, onEvent) {
  const res = await fetch(`/api/post/${encodeURIComponent(itemId)}/cancel`, { method: 'POST' });
  if (!res.ok) throw new Error('一斉中止の開始に失敗しました');
  const { job_id } = await res.json();
  return subscribeToJob(job_id, onEvent);
}

function subscribeToJob(job_id, onEvent) {
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
            if (data.type === 'error') reject(new Error(data.message || 'エラー'));
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

// ===== Event Duplicate Check =====
export async function checkDuplicateEvent({ eventDate, eventTime, excludeId }) {
  const res = await fetch('/api/check_duplicate_event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ eventDate, eventTime, excludeId }),
  });
  if (!res.ok) return { duplicate: false };
  return res.json();
}

// ===== Image Upload =====
export async function uploadImage(file) {
  const formData = new FormData();
  formData.append('image', file);
  const res = await fetch('/api/upload_image', { method: 'POST', body: formData });
  if (!res.ok) throw new Error('画像アップロードに失敗しました');
  return res.json();
}

// ===== GitHub Reviews =====
export async function fetchGithubReviews(status) {
  const query = status ? `?status=${status}` : '';
  const res = await fetch(`/api/github_reviews${query}`);
  if (!res.ok) throw new Error('GitHubレビューの取得に失敗しました');
  return res.json();
}

export async function approveGithubReview(id) {
  const res = await fetch(`/api/github_reviews/${id}/approve`, { method: 'POST' });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || '承認に失敗しました');
  }
  return res.json();
}

export async function postGithubComment(id, comment) {
  const res = await fetch(`/api/github_reviews/${id}/post_to_github`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ comment }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'GitHub投稿に失敗しました');
  }
  return res.json();
}

export async function openLocalRepo(id) {
  const res = await fetch(`/api/github_reviews/${id}/open_local`, { method: 'POST' });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'ローカルリポジトリのオープンに失敗しました');
  }
  return res.json();
}

export async function reReviewGithub(id, onEvent) {
  const res = await fetch(`/api/github_reviews/${id}/re_review`, { method: 'POST' });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || '再レビュー開始に失敗しました');
  }
  const { job_id } = await res.json();
  if (!onEvent) return { job_id };

  const cableUrl = import.meta.env.VITE_CABLE_URL || '/cable';
  const { createConsumer } = await import('@rails/actioncable');
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
            resolve();
          }
        },
        rejected() { consumer.disconnect(); reject(new Error('ActionCable接続が拒否されました')); },
      }
    );
  });
}

export async function scanGithubReviews(onEvent) {
  const res = await fetch('/api/github_reviews/scan', { method: 'POST' });
  if (!res.ok) throw new Error('スキャン開始に失敗しました');
  const { job_id } = await res.json();

  if (!onEvent) return { job_id };

  // ActionCableでリアルタイムログを受信
  const cableUrl = import.meta.env.VITE_CABLE_URL || '/cable';
  const { createConsumer } = await import('@rails/actioncable');
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
            resolve();
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

// ===== Google Calendar =====
export async function fetchCalendarEvents(start, end) {
  const res = await fetch(`/api/calendar/events?start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`);
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'カレンダーの取得に失敗しました');
  }
  const data = await res.json();
  return data.events;
}

export async function createCalendarEvent({ title, description, startTime, endTime, location }) {
  const res = await fetch('/api/calendar/events', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, description, start_time: startTime, end_time: endTime, location }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'カレンダー登録に失敗しました');
  }
  const data = await res.json();
  return data.event;
}

export async function updateCalendarEvent(eventId, { title, startTime, endTime }) {
  const res = await fetch(`/api/calendar/events/${encodeURIComponent(eventId)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, start_time: startTime, end_time: endTime }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'カレンダーイベント更新に失敗しました');
  }
  return res.json();
}

export async function deleteCalendarEvent(eventId) {
  const res = await fetch(`/api/calendar/events/${encodeURIComponent(eventId)}`, { method: 'DELETE' });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || 'カレンダーイベント削除に失敗しました');
  }
  return res.json();
}

// ===== OnClass =====
export async function uploadOnclassImage(file) {
  const formData = new FormData();
  formData.append('image', file);
  const res = await fetch('/api/onclass/upload_image', { method: 'POST', body: formData });
  if (!res.ok) throw new Error('画像アップロードに失敗しました');
  return res.json();
}

export async function fetchOnclassStudents(refresh = false) {
  const url = refresh ? '/api/onclass/students?refresh=true' : '/api/onclass/students';
  const res = await fetch(url);
  if (!res.ok) throw new Error('受講生の取得に失敗しました');
  return res.json();
}

// ===== Post (ActionCable) =====
// Returns { jobId, subscription } — caller must call subscription.unsubscribe() when done
export async function postToSites({ content, sites, eventFields, generateImage, imageStyle, openaiApiKey, dalleApiKey, itemId }, onEvent) {
  // 1. Enqueue job on Rails backend → get job_id
  const res = await fetch('/api/post', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content, sites, eventFields, generateImage, imageStyle, openaiApiKey, dalleApiKey, itemId }),
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
