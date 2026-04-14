import { useState, useEffect, useCallback } from 'react';
import { fetchCalendarEvents, createCalendarEvent, updateCalendarEvent, deleteCalendarEvent, fetchPostingHistory } from '../api.js';
import { getEventStatus } from '../eventStatus.js';

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];

const SITE_ICONS = {
  kokuchpro: '🟠', peatix: '🟡', connpass: '🔴', techplay: '🔵',
  tunagate: '🤝', doorkeeper: '🚪', street_academy: '🎓', eventregist: '📋',
  luma: '✨', seminar_biz: '💼', jimoty: '📍',
};

function CalendarEventCard({ item, s, setSelectedDate, onEditItem, onShowInList, handleSyncToGoogle, syncing, userRole }) {
  const [tags, setTags] = useState([]);
  useEffect(() => {
    if (item.item_type === 'event' || item.type === 'event') {
      fetchPostingHistory(item.id).then(d => setTags((d || []).filter(h => h.status === 'success'))).catch(() => {});
    }
  }, [item.id, item.item_type, item.type]);

  return (
    <div className={`calendar-event-card app${s === 'ended' ? ' ended' : ''}`} style={s === 'ended' ? { opacity: 0.65 } : {}}>
      <div className="calendar-event-info">
        <span className={`event-status-badge ${s}`} style={{ marginRight: 8 }}>
          {s === 'ended' ? '🔴 終了' : '🟢 募集中'}
        </span>
        <strong>{item.name}</strong>
        <span className="calendar-event-time">
          {item.eventTime || ''}{item.eventEndTime ? `〜${item.eventEndTime}` : ''}
        </span>
      </div>
      {tags.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '3px', margin: '4px 0' }}>
          {tags.map((h, i) => (
            <span key={i} style={{
              fontSize: '10px', padding: '1px 5px', borderRadius: '8px',
              background: '#dcfce7', color: '#16a34a', border: '1px solid #bbf7d0',
            }}>
              {SITE_ICONS[h.siteName] || '📌'} {h.registrations != null ? `${h.registrations}人` : ''}
            </span>
          ))}
        </div>
      )}
      <div className="calendar-event-actions">
        <button className="btn btn-sm btn-teal" onClick={() => { setSelectedDate(null); onEditItem && onEditItem(item); }}>
          {userRole === 'viewer' ? '詳細' : '編集'}
        </button>
        <button className="btn btn-sm btn-secondary" style={{ fontSize: '11px' }} onClick={() => { setSelectedDate(null); onShowInList && onShowInList(item); }}>
          📋 一覧へ
        </button>
        {userRole !== 'viewer' && <button
          className="btn btn-sm"
          style={{ background: '#e8f5e9', color: '#2e7d32', border: '1px solid #a5d6a7' }}
          onClick={() => handleSyncToGoogle(item)}
          disabled={syncing === item.id}
        >
          {syncing === item.id ? '⏳' : '📅'} GCal登録
        </button>}
      </div>
    </div>
  );
}

function getMonthDays(year, month) {
  const firstDay = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const prevDays = new Date(year, month, 0).getDate();
  const cells = [];

  // 前月の日
  for (let i = firstDay - 1; i >= 0; i--) {
    cells.push({ day: prevDays - i, current: false, date: new Date(year, month - 1, prevDays - i) });
  }
  // 当月の日
  for (let d = 1; d <= daysInMonth; d++) {
    cells.push({ day: d, current: true, date: new Date(year, month, d) });
  }
  // 次月の日（6行埋め）
  const remaining = 42 - cells.length;
  for (let d = 1; d <= remaining; d++) {
    cells.push({ day: d, current: false, date: new Date(year, month + 1, d) });
  }
  return cells;
}

function formatDateKey(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function formatTime(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d)) return '';
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

export default function CalendarView({
  items = [],
  selectedFolder = null,
  statusFilter = 'upcoming',
  onStatusFilterChange,
  onEditItem,
  onShowInList,
  onNewEvent,
  onNewStudent,
  showToast,
  userRole = 'admin',
}) {
  // フォルダ + ステータスで絞り込み
  const filteredItems = items.filter((item) => {
    if (selectedFolder) {
      const f = item.folder || '';
      if (f !== selectedFolder && !f.startsWith(selectedFolder + '/')) return false;
    }
    if (statusFilter !== 'all') {
      if (getEventStatus(item) !== statusFilter) return false;
    }
    return true;
  });
  const today = new Date();
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth());
  const [googleEvents, setGoogleEvents] = useState([]);
  const [loading, setLoading] = useState(false);
  const [selectedDate, setSelectedDate] = useState(null);
  const [syncing, setSyncing] = useState(null);
  const [editingGcal, setEditingGcal] = useState(null); // { id, title, start, end }

  const loadGoogleEvents = useCallback(async () => {
    setLoading(true);
    try {
      const start = `${year}-${String(month + 1).padStart(2, '0')}-01`;
      const endMonth = month === 11 ? 1 : month + 2;
      const endYear = month === 11 ? year + 1 : year;
      const end = `${endYear}-${String(endMonth).padStart(2, '0')}-01`;
      const events = await fetchCalendarEvents(start, end);
      setGoogleEvents(events);
    } catch (e) {
      // Googleカレンダー未連携の場合はサイレント
      setGoogleEvents([]);
    } finally {
      setLoading(false);
    }
  }, [year, month]);

  useEffect(() => {
    loadGoogleEvents();
  }, [loadGoogleEvents]);

  // アプリ内イベントを日付でマッピング（フィルタ適用後）
  const appEventsByDate = {};
  filteredItems.forEach((item) => {
    if (!item.eventDate) return;
    const key = item.eventDate;
    if (!appEventsByDate[key]) appEventsByDate[key] = [];
    appEventsByDate[key].push(item);
  });

  // Googleカレンダーイベントを日付でマッピング
  const gcalByDate = {};
  googleEvents.forEach((ev) => {
    const key = ev.start?.substring(0, 10);
    if (!key) return;
    if (!gcalByDate[key]) gcalByDate[key] = [];
    gcalByDate[key].push(ev);
  });

  const cells = getMonthDays(year, month);
  const todayKey = formatDateKey(today);

  const prevMonth = () => {
    if (month === 0) { setYear(year - 1); setMonth(11); }
    else setMonth(month - 1);
    setSelectedDate(null);
  };
  const nextMonth = () => {
    if (month === 11) { setYear(year + 1); setMonth(0); }
    else setMonth(month + 1);
    setSelectedDate(null);
  };
  const goToday = () => {
    setYear(today.getFullYear());
    setMonth(today.getMonth());
    setSelectedDate(null);
  };

  // イベントをGoogleカレンダーに登録
  const handleSyncToGoogle = async (item) => {
    if (!item.eventDate) return;
    setSyncing(item.id);
    try {
      const startTime = `${item.eventDate}T${item.eventTime || '10:00'}:00+09:00`;
      const endTime = `${item.eventDate}T${item.eventEndTime || '12:00'}:00+09:00`;
      await createCalendarEvent({
        title: item.name,
        description: item.content?.substring(0, 500) || '',
        startTime,
        endTime,
      });
      showToast('Googleカレンダーに登録しました', 'success');
      await loadGoogleEvents();
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setSyncing(null);
    }
  };

  const handleUpdateGoogleEvent = async () => {
    if (!editingGcal) return;
    try {
      await updateCalendarEvent(editingGcal.id, {
        title: editingGcal.title,
        startTime: editingGcal.start,
        endTime: editingGcal.end,
      });
      showToast('Googleカレンダーを更新しました', 'success');
      setEditingGcal(null);
      await loadGoogleEvents();
    } catch (e) {
      showToast(e.message, 'error');
    }
  };

  const handleDeleteGoogleEvent = async (eventId) => {
    try {
      await deleteCalendarEvent(eventId);
      showToast('Googleカレンダーから削除しました', 'success');
      await loadGoogleEvents();
    } catch (e) {
      showToast(e.message, 'error');
    }
  };

  // 選択した日付のイベント
  const selectedAppEvents = selectedDate ? (appEventsByDate[selectedDate] || []) : [];
  const selectedGcalEvents = selectedDate ? (gcalByDate[selectedDate] || []) : [];

  return (
    <div className="calendar-view">
      {/* アプリ説明 */}
      <div className="calendar-app-desc">
        <h2 style={{ margin: '0 0 4px', fontSize: '15px', fontWeight: 700, color: '#1e3a5f' }}>📢 イベント自動告知アプリ</h2>
        <p style={{ margin: 0, fontSize: '12px', color: '#64748b', lineHeight: 1.5 }}>
          イベントを作成し、connpass・Peatix・TechPlay・こくチーズ・Doorkeeper・つなゲートへ一括投稿。AI文章生成・Googleカレンダー連携・Zoom作成にも対応。
        </p>
      </div>

      {/* ヘッダー */}
      <div className="calendar-header">
        <button className="btn btn-sm btn-secondary" onClick={prevMonth}>&lt;</button>
        <h2 className="calendar-title">
          {year}年{month + 1}月
        </h2>
        <button className="btn btn-sm btn-secondary" onClick={nextMonth}>&gt;</button>
        <button className="btn btn-sm" onClick={goToday} style={{ marginLeft: '8px', fontSize: '11px' }}>今日</button>
        {userRole !== 'viewer' && <button
          className="btn btn-sm"
          onClick={loadGoogleEvents}
          disabled={loading}
          style={{ marginLeft: 'auto', fontSize: '11px', background: '#e8f5e9', color: '#2e7d32', border: '1px solid #a5d6a7' }}
        >
          {loading ? '⏳' : '🔄'} Google同期
        </button>}
      </div>

      {/* 凡例 + ステータスフィルタ */}
      <div className="calendar-legend" style={{ gap: 16, flexWrap: 'wrap' }}>
        <span><span className="calendar-legend-dot" style={{ background: '#ede9fe', borderColor: '#c4b5fd' }} />アプリ内イベント</span>
        <span><span className="calendar-legend-dot" style={{ background: '#dcfce7', borderColor: '#86efac' }} />Googleカレンダー</span>
        {onStatusFilterChange && (
          <div className="status-filter" role="tablist" aria-label="ステータス">
            <button
              className={statusFilter === 'upcoming' ? 'active upcoming' : ''}
              onClick={() => onStatusFilterChange('upcoming')}
            >🟢 募集中</button>
            <button
              className={statusFilter === 'ended' ? 'active ended' : ''}
              onClick={() => onStatusFilterChange('ended')}
            >🔴 終了</button>
            <button
              className={statusFilter === 'all' ? 'active' : ''}
              onClick={() => onStatusFilterChange('all')}
            >すべて</button>
          </div>
        )}
        {selectedFolder && (
          <span style={{ fontSize: 12, color: '#7c3aed', fontWeight: 600 }}>
            📂 {selectedFolder}
          </span>
        )}
      </div>

      {/* カレンダーグリッド */}
      <div className="calendar-grid">
        {WEEKDAYS.map((w, i) => (
          <div key={w} className="calendar-weekday" style={{ color: i === 0 ? '#dc2626' : i === 6 ? '#2563eb' : '#6b7280' }}>
            {w}
          </div>
        ))}
        {cells.map((cell, idx) => {
          const key = formatDateKey(cell.date);
          const isToday = key === todayKey;
          const isSelected = key === selectedDate;
          const appEvts = appEventsByDate[key] || [];
          const gcalEvts = gcalByDate[key] || [];
          const dayOfWeek = cell.date.getDay();

          return (
            <div
              key={idx}
              className={`calendar-cell${cell.current ? '' : ' other-month'}${isToday ? ' today' : ''}${isSelected ? ' selected' : ''}`}
              onClick={() => setSelectedDate(key)}
              style={{ color: dayOfWeek === 0 ? '#dc2626' : dayOfWeek === 6 ? '#2563eb' : undefined }}
            >
              <span className="calendar-day">{cell.day}</span>
              <div className="calendar-dots">
                {appEvts.slice(0, 3).map((e) => {
                  const s = getEventStatus(e);
                  return (
                    <div key={e.id} className={`calendar-dot app${s === 'ended' ? ' ended' : ''}`} title={e.name}>
                      {e.eventTime ? `${e.eventTime.substring(0, 5)}- ` : ''}{e.name}
                    </div>
                  );
                })}
                {gcalEvts.slice(0, 2).map((e) => (
                  <div key={e.id} className="calendar-dot gcal" title={e.title}>
                    {!e.allDay && e.start ? `${formatTime(e.start)}- ` : ''}{e.title}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>

      {/* 選択日のモーダル */}
      {selectedDate && (
        <div
          className="modal-overlay"
          onClick={(e) => { if (e.target === e.currentTarget) setSelectedDate(null); }}
        >
          <div className="modal" style={{ maxWidth: '560px', maxHeight: '80vh', display: 'flex', flexDirection: 'column' }}>
            <div className="modal-header">
              <h2 className="modal-title">
                {selectedDate}（{WEEKDAYS[new Date(selectedDate + 'T00:00:00').getDay()]}）
              </h2>
              <button className="modal-close" onClick={() => setSelectedDate(null)}>✕</button>
            </div>
            <div className="modal-body" style={{ overflowY: 'auto', flex: 1 }}>
              {userRole !== 'viewer' && (
                <div style={{ display: 'flex', gap: '8px', marginBottom: '16px' }}>
                  <button
                    className="btn btn-sm btn-primary"
                    onClick={() => { setSelectedDate(null); onNewEvent && onNewEvent(selectedDate); }}
                  >
                    + イベント登録
                  </button>
                  <button
                    className="btn btn-sm"
                    style={{ background: '#eef2ff', color: '#4f46e5', border: '1px solid #c7d2fe', fontSize: '12px' }}
                    onClick={() => { setSelectedDate(null); onNewStudent && onNewStudent(selectedDate); }}
                  >
                    📝 受講生サポート投稿
                  </button>
                </div>
              )}

              {selectedAppEvents.length === 0 && selectedGcalEvents.length === 0 && (
                <p style={{ color: '#9ca3af', fontSize: '13px' }}>この日のイベントはありません</p>
              )}

              {selectedAppEvents.length > 0 && (
                <div className="calendar-detail-section">
                  <h4 className="calendar-detail-label">📋 アプリ内イベント</h4>
                  {selectedAppEvents.map((item) => {
                    const s = getEventStatus(item);
                    return (
                    <CalendarEventCard key={item.id} item={item} s={s} setSelectedDate={setSelectedDate} onEditItem={onEditItem} onShowInList={onShowInList} handleSyncToGoogle={handleSyncToGoogle} syncing={syncing} userRole={userRole} />
                    );
                  })}
                </div>
              )}

              {selectedGcalEvents.length > 0 && (
                <div className="calendar-detail-section">
                  <h4 className="calendar-detail-label">📅 Googleカレンダー</h4>
                  {selectedGcalEvents.map((ev) => {
                    const isEditing = editingGcal?.id === ev.id;
                    return (
                      <div key={ev.id} className="calendar-event-card gcal">
                        {isEditing ? (
                          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', width: '100%' }}>
                            <input
                              type="text"
                              value={editingGcal.title}
                              onChange={(e) => setEditingGcal({ ...editingGcal, title: e.target.value })}
                              style={{ padding: '6px 8px', border: '1px solid #d1d5db', borderRadius: '6px', fontSize: '13px', fontWeight: 600 }}
                            />
                            <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                              <input
                                type="datetime-local"
                                value={editingGcal.start?.substring(0, 16) || ''}
                                onChange={(e) => setEditingGcal({ ...editingGcal, start: e.target.value + ':00+09:00' })}
                                style={{ padding: '4px 6px', border: '1px solid #d1d5db', borderRadius: '6px', fontSize: '12px', flex: 1 }}
                              />
                              <span style={{ color: '#9ca3af' }}>〜</span>
                              <input
                                type="datetime-local"
                                value={editingGcal.end?.substring(0, 16) || ''}
                                onChange={(e) => setEditingGcal({ ...editingGcal, end: e.target.value + ':00+09:00' })}
                                style={{ padding: '4px 6px', border: '1px solid #d1d5db', borderRadius: '6px', fontSize: '12px', flex: 1 }}
                              />
                            </div>
                            <div style={{ display: 'flex', gap: '6px' }}>
                              <button className="btn btn-sm btn-primary" onClick={handleUpdateGoogleEvent}>保存</button>
                              <button className="btn btn-sm btn-secondary" onClick={() => setEditingGcal(null)}>キャンセル</button>
                            </div>
                          </div>
                        ) : (
                          <>
                            <div className="calendar-event-info">
                              <strong>{ev.title}</strong>
                              <span className="calendar-event-time">
                                {ev.allDay ? '終日' : `${formatTime(ev.start)}${ev.end ? `〜${formatTime(ev.end)}` : ''}`}
                              </span>
                              {ev.location && <span className="calendar-event-location">📍 {ev.location}</span>}
                            </div>
                            <div className="calendar-event-actions">
                              <button
                                className="btn btn-sm btn-teal"
                                onClick={() => setEditingGcal({ id: ev.id, title: ev.title || '', start: ev.start || '', end: ev.end || '' })}
                              >
                                編集
                              </button>
                              {ev.htmlLink && (
                                <a href={ev.htmlLink} target="_blank" rel="noopener noreferrer" className="btn btn-sm btn-secondary" style={{ fontSize: '11px', textDecoration: 'none' }}>
                                  開く
                                </a>
                              )}
                              <button
                                className="btn btn-sm"
                                style={{ fontSize: '11px', color: '#dc2626', background: '#fee2e2', border: '1px solid #fca5a5' }}
                                onClick={() => handleDeleteGoogleEvent(ev.id)}
                              >
                                削除
                              </button>
                            </div>
                          </>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
