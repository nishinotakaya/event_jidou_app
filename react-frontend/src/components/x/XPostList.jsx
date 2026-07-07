import { xDeletePost, xPostNow } from './xApi.js';

const STATUS_BADGE = {
  pending: { label: '予約中', bg: '#f5f0ff', color: '#6b4fa0', border: '#ddd5f0' },
  posted:  { label: '投稿済', bg: '#dcfce7', color: '#166534', border: '#86efac' },
  failed:  { label: '失敗',   bg: '#fee2e2', color: '#b91c1c', border: '#fca5a5' },
};

function formatScheduledAt(iso) {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d)) return '-';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export default function XPostList({ posts, loading, onEdit, onChanged, onNeedConnect, showToast }) {
  async function handleDelete(post) {
    if (!confirm('この予約ツイートを削除しますか？')) return;
    try {
      await xDeletePost(post.id);
      showToast?.('削除しました', 'success');
      onChanged?.();
    } catch (err) {
      showToast?.(err.message, 'error');
    }
  }

  async function handlePostNow(post) {
    const isRetry = post.status === 'failed';
    const confirmMsg = isRetry ? 'この投稿を X に再投稿しますか？' : '今すぐ X に投稿しますか？';
    if (!confirm(confirmMsg)) return;

    const result = await xPostNow(post.id);
    if (result.ok) {
      showToast?.('X に投稿しました', 'success');
      onChanged?.();
      return;
    }

    // 未接続なら接続設定へ誘導
    if (result.needsConnect) {
      showToast?.('X が未接続です。接続設定を開きます', 'error');
      onNeedConnect?.();
      return;
    }
    showToast?.(result.error || '投稿に失敗しました', 'error');
    onChanged?.();
  }

  if (loading) {
    return <div style={{ padding: '40px', textAlign: 'center', color: '#9878cc' }}>読み込み中…</div>;
  }
  if (!posts.length) {
    return (
      <div style={{ padding: '40px', textAlign: 'center', color: '#9878cc' }}>
        まだ予約ツイートはありません。「新規作成」か「AIで1ヶ月分まとめて作る」から始められます。
      </div>
    );
  }

  return (
    <div style={{ overflow: 'auto', border: '1.5px solid #e2d9f3', borderRadius: '12px', background: '#fff' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
        <thead>
          <tr style={{ background: '#faf8ff', color: '#6b4fa0' }}>
            <th style={th()}>投稿時刻</th>
            <th style={th()}>本文</th>
            <th style={{ ...th(), width: 60 }}>画像</th>
            <th style={{ ...th(), width: 80 }}>状態</th>
            <th style={{ ...th(), width: 240 }}>操作</th>
          </tr>
        </thead>
        <tbody>
          {posts.map((post) => {
            const badge = STATUS_BADGE[post.status] || STATUS_BADGE.pending;
            return (
              <tr key={post.id} style={{ borderTop: '1px solid #f0ecf8' }}>
                <td style={td()}>{formatScheduledAt(post.scheduledAt)}</td>
                <td style={{ ...td(), color: '#2d1b52', whiteSpace: 'pre-wrap', maxWidth: 420 }}>
                  {post.content}
                  {post.status === 'failed' && post.errorMessage && (
                    <div style={{
                      marginTop: 6,
                      fontSize: '11px',
                      color: '#b91c1c',
                      background: '#fef2f2',
                      border: '1px solid #fecaca',
                      borderRadius: 6,
                      padding: '4px 8px',
                      whiteSpace: 'pre-wrap',
                      wordBreak: 'break-word',
                    }}>
                      失敗理由: {post.errorMessage}
                    </div>
                  )}
                </td>
                <td style={td()}>
                  {post.imageUrl
                    ? <img src={post.imageUrl} alt="" style={{ width: 40, height: 40, objectFit: 'cover', borderRadius: 6, border: '1px solid #e2d9f3' }} />
                    : <span style={{ color: '#cbd5e1' }}>-</span>}
                </td>
                <td style={td()}>
                  <span style={{
                    fontSize: '11px',
                    padding: '2px 8px',
                    borderRadius: '999px',
                    background: badge.bg,
                    color: badge.color,
                    border: `1px solid ${badge.border}`,
                    fontWeight: 600,
                  }}>
                    {badge.label}
                  </span>
                </td>
                <td style={td()}>
                  <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                    <button className="btn btn-sm btn-secondary" onClick={() => onEdit?.(post)}>編集</button>
                    {post.status === 'failed' ? (
                      <button
                        className="btn btn-sm"
                        style={{ background: '#fff7ed', color: '#c2410c', border: '1px solid #fed7aa', fontWeight: 600 }}
                        onClick={() => handlePostNow(post)}
                      >
                        再投稿
                      </button>
                    ) : (
                      <button
                        className="btn btn-sm"
                        style={{ background: '#f0fdf4', color: '#166534', border: '1px solid #bbf7d0' }}
                        onClick={() => handlePostNow(post)}
                        disabled={post.status === 'posted'}
                      >
                        今すぐ
                      </button>
                    )}
                    {post.status === 'posted' && post.tweetUrl && (
                      <a
                        className="btn btn-sm"
                        href={post.tweetUrl}
                        target="_blank"
                        rel="noreferrer"
                        style={{ background: '#eff6ff', color: '#1d4ed8', border: '1px solid #bfdbfe', textDecoration: 'none' }}
                      >
                        開く
                      </a>
                    )}
                    <button className="btn btn-sm btn-danger" onClick={() => handleDelete(post)}>削除</button>
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function th() {
  return { textAlign: 'left', padding: '10px 12px', fontSize: '12px', fontWeight: 700, borderBottom: '1.5px solid #e2d9f3' };
}

function td() {
  return { padding: '10px 12px', verticalAlign: 'top' };
}
