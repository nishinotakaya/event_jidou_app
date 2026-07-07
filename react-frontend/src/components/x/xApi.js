// X 自動投稿 API クライアント。
// バックエンド (rails-backend/app/controllers/api/x_controller.rb) の実 API を叩く。
// 401（未ログイン）等のエラー時は空配列/null を返してフロントが落ちないようにする。
// モックフォールバックは localhost 開発時のみ有効。
//
// バックエンドのレスポンス形:
//   GET    /api/x/posts          → { posts: [...] }
//   POST   /api/x/posts          → { post: {...} }
//   PUT    /api/x/posts/:id      → { post: {...} }
//   DELETE /api/x/posts/:id      → { ok: true }
//   POST   /api/x/posts/:id/post_now → { ok, post }
//   POST   /api/x/generate_month → { posts: [...] }
//   POST   /api/x/connect        → { ok, screen_name, id, name }
//   POST   /api/x/test           → { ok, screen_name } | { ok:false, error }
//   GET    /api/x/status         → { connected, screen_name?, last_connected_at, pending_count, posted_count, failed_count }
//
// scheduled_at / posted_at / tweet_url / image_url 等は snake_case → camelCase に変換して返す。

const IS_LOCALHOST = typeof window !== 'undefined' && window.location?.hostname === 'localhost';

function toCamelPost(p) {
  if (!p || typeof p !== 'object') return p;
  return {
    id: p.id,
    content: p.content,
    imageUrl: p.image_url ?? null,
    scheduledAt: p.scheduled_at ?? null,
    status: p.status,
    postedAt: p.posted_at ?? null,
    tweetUrl: p.tweet_url ?? null,
    errorMessage: p.error_message ?? null,
    source: p.source,
    itemId: p.item_id ?? null,
  };
}

function toCamelStatus(s) {
  if (!s || typeof s !== 'object') return { connected: false };
  return {
    connected: !!s.connected,
    screenName: s.screen_name ?? s.screenName ?? null,
    lastConnectedAt: s.last_connected_at ?? s.lastConnectedAt ?? null,
    pendingCount: s.pending_count ?? 0,
    postedCount: s.posted_count ?? 0,
    failedCount: s.failed_count ?? 0,
  };
}

async function callApi(url, init) {
  try {
    const res = await fetch(url, init);
    if (!res.ok) return { ok: false, status: res.status };
    const data = await res.json();
    return { ok: true, data };
  } catch (e) {
    return { ok: false, error: e?.message };
  }
}

export async function xListPosts({ from, to } = {}) {
  const qs = new URLSearchParams();
  if (from) qs.set('from', from);
  if (to) qs.set('to', to);
  const r = await callApi(`/api/x/posts${qs.toString() ? `?${qs}` : ''}`);
  if (!r.ok) return [];
  const arr = Array.isArray(r.data?.posts) ? r.data.posts : Array.isArray(r.data) ? r.data : [];
  return arr.map(toCamelPost);
}

export async function xCreatePost(payload) {
  const body = {
    content: payload.content,
    scheduled_at: payload.scheduledAt ?? payload.scheduled_at,
    image_url: payload.imageUrl ?? payload.image_url ?? null,
    source: payload.source || 'manual',
    item_id: payload.itemId ?? payload.item_id ?? null,
  };
  const r = await callApi('/api/x/posts', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`X 投稿の作成に失敗: HTTP ${r.status || r.error}`);
  return toCamelPost(r.data?.post || r.data);
}

export async function xUpdatePost(id, payload) {
  const body = {};
  if (payload.content !== undefined) body.content = payload.content;
  if (payload.scheduledAt !== undefined || payload.scheduled_at !== undefined) {
    body.scheduled_at = payload.scheduledAt ?? payload.scheduled_at;
  }
  if (payload.imageUrl !== undefined || payload.image_url !== undefined) {
    body.image_url = payload.imageUrl ?? payload.image_url;
  }
  const r = await callApi(`/api/x/posts/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`X 投稿の更新に失敗: HTTP ${r.status || r.error}`);
  return toCamelPost(r.data?.post || r.data);
}

export async function xDeletePost(id) {
  const r = await callApi(`/api/x/posts/${id}`, { method: 'DELETE' });
  if (!r.ok) throw new Error(`X 投稿の削除に失敗: HTTP ${r.status || r.error}`);
  return { ok: true };
}

// 即時投稿 / 失敗投稿の再投稿。バックエンドが同期で X API を叩くため、
// ここで成功/失敗が確定する。throw せず { ok, error, needsConnect, post } を返し、
// 呼び出し側が未接続なら接続モーダルへ誘導できるようにする。
export async function xPostNow(id) {
  const r = await callApi(`/api/x/posts/${id}/post_now`, { method: 'POST' });
  const post = r.data?.post ? toCamelPost(r.data.post) : null;
  if (r.ok && r.data?.ok) {
    return { ok: true, post };
  }
  return {
    ok: false,
    error: r.data?.error || `投稿に失敗しました（HTTP ${r.status || r.error}）`,
    needsConnect: !!r.data?.needs_connect,
    post,
  };
}

// AI 1 ヶ月分生成は OpenAI 呼び出しが 30 秒超になり Heroku ルーターが切るため、
// Sidekiq に投げて ActionCable("XGenerateChannel") で結果を待つ。
// onLog: 進捗ログを受け取るコールバック (任意)
export async function xGenerateMonth({ theme, startDate, postsPerDay, timeSlots, days, dryRun, onLog } = {}) {
  const body = {
    extra_theme: theme,
    start_date: startDate,
    per_day: postsPerDay,
    time_slots: timeSlots,
    days: days ?? 30,
    dry_run: !!dryRun,
  };
  const r = await callApi('/api/x/generate_month', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`AI 生成リクエストに失敗: HTTP ${r.status || r.error}`);
  const jobId = r.data?.job_id;
  if (!jobId) throw new Error('job_id が返ってきませんでした');

  // ActionCable で進捗購読
  const { createConsumer } = await import('@rails/actioncable');
  const cableUrl = typeof window !== 'undefined' && window.location?.hostname === 'localhost'
    ? '/cable'
    : 'wss://announcement-d656a48fc066.herokuapp.com/cable';

  return new Promise((resolve, reject) => {
    const cable = createConsumer(cableUrl);
    const timer = setTimeout(() => {
      try { sub.unsubscribe(); } catch { /* noop */ }
      try { cable.disconnect(); } catch { /* noop */ }
      reject(new Error('AI 生成タイムアウト（5 分）'));
    }, 5 * 60 * 1000);
    const sub = cable.subscriptions.create(
      { channel: 'XGenerateChannel', job_id: jobId },
      {
        received(event) {
          if (event?.type === 'log' && onLog) onLog(event.message);
          if (event?.type === 'done') {
            clearTimeout(timer);
            try { sub.unsubscribe(); } catch { /* noop */ }
            try { cable.disconnect(); } catch { /* noop */ }
            const drafts = (event.posts || event.planned || []).map(toCamelPost);
            resolve({ drafts });
          } else if (event?.type === 'error') {
            clearTimeout(timer);
            try { sub.unsubscribe(); } catch { /* noop */ }
            try { cable.disconnect(); } catch { /* noop */ }
            reject(new Error(event.message || 'AI 生成エラー'));
          }
        },
      },
    );
  });
}

export async function xConnect({ authToken, ct0 }) {
  const r = await callApi('/api/x/connect', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ auth_token: authToken, ct0 }),
  });
  if (!r.ok) {
    return { ok: false, error: r.data?.error || `HTTP ${r.status || r.error}` };
  }
  return { ok: true, screenName: r.data?.screen_name, id: r.data?.id, name: r.data?.name };
}

export async function xTestConnection() {
  const r = await callApi('/api/x/test', { method: 'POST' });
  if (!r.ok) return { ok: false, error: `HTTP ${r.status || r.error}` };
  return { ok: !!r.data?.ok, screenName: r.data?.screen_name, error: r.data?.error };
}

export async function xFetchStatus() {
  const r = await callApi('/api/x/status');
  if (!r.ok) return toCamelStatus({ connected: false });
  return toCamelStatus(r.data);
}
