import { useState, useEffect, useMemo } from 'react';
import { fetchTexts, fetchPostingHistory } from '../api.js';

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

function dateKey(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

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
    const last = cells[cells.length - 1].date;
    const next = new Date(last);
    next.setDate(last.getDate() + 1);
    cells.push({ day: next.getDate(), current: false, date: next });
  }
  return cells;
}

// 月内のイベント分の posting_history をまとめて引き、日付ごとに { published, draft, error } を作る
async function loadMonthlySummary(items, fromKey, toKey) {
  const visible = items.filter((it) => it.eventDate && it.eventDate >= fromKey && it.eventDate <= toKey);
  const summaryByDate = {};
  const detailByDate = {}; // dateKey -> [{ item, histories }]

  for (const item of visible) {
    let histories = [];
    try {
      histories = await fetchPostingHistory(item.id);
    } catch {
      histories = [];
    }
    const key = item.eventDate;
    if (!summaryByDate[key]) summaryByDate[key] = { published: 0, draft: 0, error: 0 };
    if (!detailByDate[key]) detailByDate[key] = [];
    detailByDate[key].push({ item, histories: histories || [] });
    (histories || []).forEach((h) => {
      if (h.status === 'error' || h.status === 'not_found') summaryByDate[key].error += 1;
      else if (h.published) summaryByDate[key].published += 1;
      else summaryByDate[key].draft += 1;
    });
  }
  return { summaryByDate, detailByDate };
}

export default function AnnouncementPanel({ showToast }) {
  const today = new Date();
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth());
  const [summary, setSummary] = useState({});
  const [detail, setDetail] = useState({});
  const [loading, setLoading] = useState(false);
  const [selectedDate, setSelectedDate] = useState(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        let list = [];
        try {
          list = await fetchTexts('event');
        } catch (err) {
          showToast?.(`イベント取得に失敗: ${err.message}`, 'error');
          list = [];
        }
        if (cancelled) return;

        const pad = (n) => String(n).padStart(2, '0');
        const fromKey = `${year}-${pad(month + 1)}-01`;
        const lastDay = new Date(year, month + 1, 0).getDate();
        const toKey = `${year}-${pad(month + 1)}-${pad(lastDay)}`;
        const { summaryByDate, detailByDate } = await loadMonthlySummary(list, fromKey, toKey);
        if (cancelled) return;
        setSummary(summaryByDate);
        setDetail(detailByDate);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [year, month, showToast]);

  const cells = useMemo(() => getMonthCells(year, month), [year, month]);
  const todayKey = dateKey(today);
  const selectedDetail = selectedDate ? (detail[selectedDate] || []) : [];

  const totals = useMemo(() => {
    return Object.values(summary).reduce(
      (acc, s) => ({ published: acc.published + s.published, draft: acc.draft + s.draft, error: acc.error + s.error }),
      { published: 0, draft: 0, error: 0 }
    );
  }, [summary]);

  return (
    <div style={{ padding: '0 24px 24px' }}>
      <div style={{
        background: '#faf8ff',
        border: '1.5px solid #e2d9f3',
        borderRadius: '12px',
        padding: '14px 18px',
        marginBottom: '16px',
        display: 'flex',
        alignItems: 'center',
        gap: '16px',
        flexWrap: 'wrap',
      }}>
        <div>
          <h2 style={{ margin: 0, fontSize: '16px', color: '#3b1f6e' }}>告知ダッシュボード</h2>
          <p style={{ margin: '2px 0 0', fontSize: '12px', color: '#6b4fa0' }}>
            ポータルサイトへの投稿状況を月単位で集約。色付きバッジは「公開済み / 下書き / エラー」の件数。
          </p>
        </div>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: '8px', fontSize: '12px' }}>
          <Badge bg="#dcfce7" color="#166534" border="#86efac">公開 {totals.published}</Badge>
          <Badge bg="#f5f0ff" color="#6b4fa0" border="#ddd5f0">下書き {totals.draft}</Badge>
          <Badge bg="#fee2e2" color="#b91c1c" border="#fca5a5">エラー {totals.error}</Badge>
        </div>
      </div>

      <div className="calendar-view">
        <div className="calendar-header">
          <button
            className="btn btn-sm btn-secondary"
            onClick={() => { if (month === 0) { setYear(year - 1); setMonth(11); } else setMonth(month - 1); }}
          >&lt;</button>
          <h2 className="calendar-title">{year}年{month + 1}月</h2>
          <button
            className="btn btn-sm btn-secondary"
            onClick={() => { if (month === 11) { setYear(year + 1); setMonth(0); } else setMonth(month + 1); }}
          >&gt;</button>
          <button
            className="btn btn-sm"
            onClick={() => { setYear(today.getFullYear()); setMonth(today.getMonth()); }}
            style={{ marginLeft: '8px', fontSize: '11px' }}
          >今日</button>
          {loading && <span style={{ marginLeft: '12px', fontSize: '12px', color: '#9878cc' }}>読み込み中…</span>}
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
            const s = summary[key];
            const dayOfWeek = cell.date.getDay();
            return (
              <div
                key={idx}
                className={`calendar-cell${cell.current ? '' : ' other-month'}${isToday ? ' today' : ''}`}
                onClick={() => { if (s) setSelectedDate(key); }}
                style={{ color: dayOfWeek === 0 ? '#dc2626' : dayOfWeek === 6 ? '#2563eb' : undefined, cursor: s ? 'pointer' : 'default' }}
              >
                <span className="calendar-day">{cell.day}</span>
                {s && (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 2, marginTop: 2 }}>
                    {s.published > 0 && <MiniBadge bg="#dcfce7" color="#166534">公開 {s.published}</MiniBadge>}
                    {s.draft     > 0 && <MiniBadge bg="#f5f0ff" color="#6b4fa0">下書き {s.draft}</MiniBadge>}
                    {s.error     > 0 && <MiniBadge bg="#fee2e2" color="#b91c1c">エラー {s.error}</MiniBadge>}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {selectedDate && (
        <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) setSelectedDate(null); }}>
          <div className="modal" style={{ maxWidth: '640px' }}>
            <div className="modal-header">
              <h2 className="modal-title">{selectedDate} の告知状況</h2>
              <button className="modal-close" onClick={() => setSelectedDate(null)}>✕</button>
            </div>
            <div className="modal-body">
              {selectedDetail.length === 0 && <p style={{ color: '#9878cc' }}>この日のイベントはありません。</p>}
              {selectedDetail.map(({ item, histories }) => (
                <div key={item.id} style={{ border: '1.5px solid #e2d9f3', borderRadius: '10px', padding: '12px' }}>
                  <div style={{ fontWeight: 700, color: '#2d1b52', marginBottom: '4px' }}>{item.name}</div>
                  <div style={{ fontSize: '12px', color: '#6b7280', marginBottom: '8px' }}>
                    {item.eventTime || ''}{item.eventEndTime ? ` 〜 ${item.eventEndTime}` : ''}
                  </div>
                  {histories.length === 0
                    ? <div style={{ fontSize: '12px', color: '#9878cc' }}>投稿履歴なし</div>
                    : (
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                        {histories.map((h, i) => {
                          const isError = h.status === 'error' || h.status === 'not_found';
                          const bg = isError ? '#fee2e2' : h.published ? '#dcfce7' : '#f5f0ff';
                          const color = isError ? '#b91c1c' : h.published ? '#166534' : '#6b4fa0';
                          const border = isError ? '#fca5a5' : h.published ? '#86efac' : '#ddd5f0';
                          return (
                            <a
                              key={i}
                              href={h.eventUrl || '#'}
                              target={h.eventUrl ? '_blank' : undefined}
                              rel="noopener noreferrer"
                              onClick={(e) => { if (!h.eventUrl) e.preventDefault(); }}
                              style={{
                                fontSize: '11px',
                                padding: '3px 8px',
                                borderRadius: '999px',
                                background: bg,
                                color,
                                border: `1px solid ${border}`,
                                textDecoration: 'none',
                                fontWeight: 600,
                              }}
                            >
                              {h.siteLabel || h.siteName} {isError ? '× エラー' : h.published ? '✓ 公開' : '✎ 下書き'}
                            </a>
                          );
                        })}
                      </div>
                    )}
                </div>
              ))}
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setSelectedDate(null)}>閉じる</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Badge({ bg, color, border, children }) {
  return (
    <span style={{
      padding: '4px 10px',
      borderRadius: '999px',
      background: bg,
      color,
      border: `1px solid ${border}`,
      fontWeight: 700,
    }}>{children}</span>
  );
}

function MiniBadge({ bg, color, children }) {
  return (
    <span style={{
      fontSize: 10,
      padding: '1px 5px',
      borderRadius: 4,
      background: bg,
      color,
      fontWeight: 600,
      whiteSpace: 'nowrap',
    }}>{children}</span>
  );
}
