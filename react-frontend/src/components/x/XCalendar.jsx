import { useState, useMemo } from 'react';
import { xPostNow } from './xApi.js';

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

function getMonthCells(year, month) {
  const firstDay = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const prevDays = new Date(year, month, 0).getDate();
  const cells = [];
  for (let i = firstDay - 1; i >= 0; i--) {
    cells.push({ day: prevDays - i, current: false, date: new Date(year, month - 1, prevDays - i) });
  }
  for (let d = 1; d <= daysInMonth; d++) {
    cells.push({ day: d, current: true, date: new Date(year, month, d) });
  }
  while (cells.length < 42) {
    const lastDate = cells[cells.length - 1].date;
    const next = new Date(lastDate);
    next.setDate(lastDate.getDate() + 1);
    cells.push({ day: next.getDate(), current: false, date: next });
  }
  return cells;
}

function dateKey(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// X の1日投稿上限等で先送りされた pending 投稿かどうかを判定する。
function isRetryWaiting(post) {
  return !!post.retryWaiting || (post.status === 'pending' && !!post.errorMessage);
}

function formatTime(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export default function XCalendar({ posts, onEditPost, onCreateOnDate, onChanged, onNeedConnect, showToast }) {
  const today = new Date();
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth());
  const [selectedDate, setSelectedDate] = useState(null);
  const [postingId, setPostingId] = useState(null);

  // 一覧と同じく X へ即時投稿する。成功/失敗は xPostNow が { ok, error, needsConnect } で返す。
  async function handlePostNow(post) {
    const isRetry = post.status === 'failed';
    const confirmMsg = isRetry ? 'この投稿を X に再投稿しますか？' : '今すぐ X に投稿しますか？';
    if (!window.confirm(confirmMsg)) return;

    setPostingId(post.id);
    try {
      const result = await xPostNow(post.id);
      if (result.ok) {
        showToast?.('X に投稿しました', 'success');
        setSelectedDate(null);
        onChanged?.();
        return;
      }
      if (result.needsConnect) {
        showToast?.('X が未接続です。接続設定を開きます', 'error');
        setSelectedDate(null);
        onNeedConnect?.();
        return;
      }
      showToast?.(result.error || '投稿に失敗しました', 'error');
      onChanged?.();
    } finally {
      setPostingId(null);
    }
  }

  const postsByDate = useMemo(() => {
    const map = {};
    posts.forEach((p) => {
      const d = new Date(p.scheduledAt);
      if (isNaN(d)) return;
      const key = dateKey(d);
      if (!map[key]) map[key] = [];
      map[key].push(p);
    });
    Object.values(map).forEach((arr) => arr.sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt)));
    return map;
  }, [posts]);

  const cells = getMonthCells(year, month);
  const todayKey = dateKey(today);
  const selected = selectedDate ? (postsByDate[selectedDate] || []) : [];

  const prevMonth = () => {
    if (month === 0) { setYear(year - 1); setMonth(11); } else setMonth(month - 1);
    setSelectedDate(null);
  };
  const nextMonth = () => {
    if (month === 11) { setYear(year + 1); setMonth(0); } else setMonth(month + 1);
    setSelectedDate(null);
  };
  const goToday = () => { setYear(today.getFullYear()); setMonth(today.getMonth()); setSelectedDate(null); };

  return (
    <div className="calendar-view">
      <div className="calendar-header">
        <button className="btn btn-sm btn-secondary" onClick={prevMonth}>&lt;</button>
        <h2 className="calendar-title">{year}年{month + 1}月</h2>
        <button className="btn btn-sm btn-secondary" onClick={nextMonth}>&gt;</button>
        <button className="btn btn-sm" onClick={goToday} style={{ marginLeft: '8px', fontSize: '11px' }}>今日</button>
        <span style={{ marginLeft: 'auto', fontSize: '12px', color: '#6b4fa0' }}>
          合計 {posts.length} 件
        </span>
      </div>

      <div className="calendar-grid">
        {WEEKDAYS.map((w, i) => (
          <div key={w} className="calendar-weekday" style={{ color: i === 0 ? '#dc2626' : i === 6 ? '#2563eb' : '#6b7280' }}>
            {w}
          </div>
        ))}
        {cells.map((cell, idx) => {
          const key = dateKey(cell.date);
          const isToday = key === todayKey;
          const isSelected = key === selectedDate;
          const dayPosts = postsByDate[key] || [];
          const dayOfWeek = cell.date.getDay();
          return (
            <div
              key={idx}
              className={`calendar-cell${cell.current ? '' : ' other-month'}${isToday ? ' today' : ''}${isSelected ? ' selected' : ''}`}
              onClick={() => setSelectedDate(key)}
              style={{ color: dayOfWeek === 0 ? '#dc2626' : dayOfWeek === 6 ? '#2563eb' : undefined }}
            >
              <span className="calendar-day">{cell.day}</span>
              {dayPosts.length > 0 && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2, marginTop: 2 }}>
                  {dayPosts.slice(0, 3).map((p) => (
                    <div
                      key={p.id}
                      style={{
                        fontSize: 10,
                        background: p.status === 'posted' ? '#dcfce7' : p.status === 'failed' ? '#fee2e2' : isRetryWaiting(p) ? '#fef3c7' : '#ede9fe',
                        color: p.status === 'posted' ? '#166534' : p.status === 'failed' ? '#b91c1c' : isRetryWaiting(p) ? '#92400e' : '#5b21b6',
                        borderRadius: 4,
                        padding: '1px 4px',
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                      }}
                      title={p.content}
                    >
                      {formatTime(p.scheduledAt)} {p.content.slice(0, 12)}
                    </div>
                  ))}
                  {dayPosts.length > 3 && (
                    <div style={{ fontSize: 10, color: '#7c3aed', fontWeight: 600 }}>
                      +{dayPosts.length - 3} 件
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {selectedDate && (
        <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) setSelectedDate(null); }}>
          <div className="modal" style={{ maxWidth: '560px' }}>
            <div className="modal-header">
              <h2 className="modal-title">{selectedDate} の予約ツイート（{selected.length}件）</h2>
              <button className="modal-close" onClick={() => setSelectedDate(null)}>✕</button>
            </div>
            <div className="modal-body">
              {selected.length === 0 && <p style={{ color: '#9878cc', fontSize: '13px' }}>この日には予約がありません。</p>}
              {selected.map((p) => (
                <div
                  key={p.id}
                  style={{ border: '1.5px solid #e2d9f3', borderRadius: '10px', padding: '10px 12px', marginBottom: '8px' }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '4px' }}>
                    <span style={{ fontSize: '12px', color: '#6b4fa0', fontWeight: 600 }}>
                      {formatTime(p.scheduledAt)}
                    </span>
                    {p.status === 'posted' && (
                      <span style={{ fontSize: '11px', padding: '1px 8px', borderRadius: '999px', background: '#dcfce7', color: '#166534', border: '1px solid #86efac', fontWeight: 600 }}>投稿済</span>
                    )}
                    {p.status === 'failed' && (
                      <span style={{ fontSize: '11px', padding: '1px 8px', borderRadius: '999px', background: '#fee2e2', color: '#b91c1c', border: '1px solid #fca5a5', fontWeight: 600 }}>失敗</span>
                    )}
                    {isRetryWaiting(p) && (
                      <span style={{ fontSize: '11px', padding: '1px 8px', borderRadius: '999px', background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d', fontWeight: 600 }}>再送待ち</span>
                    )}
                  </div>
                  <div
                    style={{ fontSize: '13px', color: '#2d1b52', whiteSpace: 'pre-wrap', cursor: 'pointer' }}
                    onClick={() => { setSelectedDate(null); onEditPost?.(p); }}
                    title="クリックで編集"
                  >
                    {p.content}
                  </div>
                  {p.status === 'failed' && p.errorMessage && (
                    <div style={{ marginTop: 6, fontSize: '11px', color: '#b91c1c', background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 6, padding: '4px 8px', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                      失敗理由: {p.errorMessage}
                    </div>
                  )}
                  {isRetryWaiting(p) && p.errorMessage && (
                    <div style={{ marginTop: 6, fontSize: '11px', color: '#92400e', background: '#fffbeb', border: '1px solid #fde68a', borderRadius: 6, padding: '4px 8px', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                      再送待ち: {p.errorMessage}
                    </div>
                  )}
                  <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', marginTop: '8px' }}>
                    <button
                      className="btn btn-sm btn-secondary"
                      onClick={(e) => { e.stopPropagation(); setSelectedDate(null); onEditPost?.(p); }}
                    >
                      編集
                    </button>
                    {p.status === 'failed' ? (
                      <button
                        className="btn btn-sm"
                        style={{ background: '#fff7ed', color: '#c2410c', border: '1px solid #fed7aa', fontWeight: 600 }}
                        onClick={(e) => { e.stopPropagation(); handlePostNow(p); }}
                        disabled={postingId === p.id}
                      >
                        {postingId === p.id ? '投稿中…' : '再投稿'}
                      </button>
                    ) : (
                      <button
                        className="btn btn-sm"
                        style={{ background: '#f0fdf4', color: '#166534', border: '1px solid #bbf7d0', fontWeight: 600 }}
                        onClick={(e) => { e.stopPropagation(); handlePostNow(p); }}
                        disabled={p.status === 'posted' || postingId === p.id}
                      >
                        {postingId === p.id ? '投稿中…' : '今すぐ投稿'}
                      </button>
                    )}
                    {p.status === 'posted' && p.tweetUrl && (
                      <a
                        className="btn btn-sm"
                        href={p.tweetUrl}
                        target="_blank"
                        rel="noreferrer"
                        style={{ background: '#eff6ff', color: '#1d4ed8', border: '1px solid #bfdbfe', textDecoration: 'none' }}
                        onClick={(e) => e.stopPropagation()}
                      >
                        開く
                      </a>
                    )}
                  </div>
                </div>
              ))}
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setSelectedDate(null)}>閉じる</button>
              <button
                className="btn btn-primary"
                onClick={() => { onCreateOnDate?.(selectedDate); setSelectedDate(null); }}
              >
                この日に新規作成
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
