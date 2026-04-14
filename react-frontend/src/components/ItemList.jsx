import { useState } from 'react';
import ItemCard from './ItemCard.jsx';
import { getEventStatus, statusMatchesQuery } from '../eventStatus.js';
import { syncParticipants } from '../api.js';

const PAGE_SIZE = 9;

function Pagination({ page, totalPages, totalItems, onPageChange }) {
  if (totalPages <= 1) return null;

  const renderPages = () => {
    const items = [];
    const addBtn = (i) => items.push(
      <button
        key={i}
        className={`pagination-btn ${i === page ? 'active' : ''}`}
        onClick={() => onPageChange(i)}
      >
        {i}
      </button>
    );
    const addEllipsis = (key) => items.push(
      <span key={key} className="pagination-ellipsis">...</span>
    );

    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) addBtn(i);
    } else {
      addBtn(1);
      if (page > 3) addEllipsis('el1');
      const start = Math.max(2, page - 1);
      const end = Math.min(totalPages - 1, page + 1);
      for (let i = start; i <= end; i++) addBtn(i);
      if (page < totalPages - 2) addEllipsis('el2');
      addBtn(totalPages);
    }
    return items;
  };

  const from = (page - 1) * PAGE_SIZE + 1;
  const to = Math.min(page * PAGE_SIZE, totalItems);

  return (
    <div className="pagination">
      <span className="pagination-info">{from}-{to} / {totalItems}件</span>
      <button
        className="pagination-btn nav"
        onClick={() => onPageChange(page - 1)}
        disabled={page === 1}
      >
        ← 前
      </button>
      {renderPages()}
      <button
        className="pagination-btn nav"
        onClick={() => onPageChange(page + 1)}
        disabled={page === totalPages}
      >
        次 →
      </button>
    </div>
  );
}

export default function ItemList({
  items,
  loading,
  type,
  folders,
  selectedFolder,
  onEdit,
  onDelete,
  onBulkDelete,
  onPost,
  onDuplicate,
  onCancel,
  onRefresh,
  showToast,
  page,
  onPageChange,
  searchQuery = '',
  sortOrder = 'eventDate-desc',
  statusFilter = 'upcoming',
  onScanGithub,
  userRole = 'admin',
}) {
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [selectMode, setSelectMode] = useState(false);
  const [allTagsOpen, setAllTagsOpen] = useState(true);

  // 月ナビゲーション（フォルダ内 月単位移動）
  const now = new Date();
  const [monthCursor, setMonthCursor] = useState({ year: now.getFullYear(), month: now.getMonth() }); // month: 0-11
  const [monthFilterEnabled, setMonthFilterEnabled] = useState(false);

  // Filter items by selected folder + search query
  // 親フォルダ選択時は子フォルダのアイテムも含める（前方一致）
  let filtered = selectedFolder
    ? items.filter((item) => {
        const f = item.folder || '';
        return f === selectedFolder || f.startsWith(selectedFolder + '/');
      })
    : items;

  // 月フィルタ（有効時のみ）
  if (monthFilterEnabled) {
    const ym = `${monthCursor.year}-${String(monthCursor.month + 1).padStart(2, '0')}`;
    filtered = filtered.filter((item) => (item.eventDate || '').startsWith(ym));
  }

  if (searchQuery.trim()) {
    const raw = searchQuery.trim();
    const q = raw.toLowerCase();
    filtered = filtered.filter((item) => {
      const status = getEventStatus(item);
      if (raw.includes('終了') || raw.includes('募集中') || raw.includes('開催前')) {
        return statusMatchesQuery(status, raw);
      }
      return (
        (item.name || '').toLowerCase().includes(q) ||
        (item.content || '').toLowerCase().includes(q) ||
        (item.eventDate || '').includes(q) ||
        (item.folder || '').toLowerCase().includes(q)
      );
    });
  }

  // ステータスフィルタ（タイプ=event のみ適用。受講生サポートには不適用）
  if (type === 'event' && statusFilter !== 'all') {
    filtered = filtered.filter((item) => getEventStatus(item) === statusFilter);
  }

  // Sort
  filtered = [...filtered].sort((a, b) => {
    if (sortOrder === 'eventDate-desc') return (b.eventDate || '').localeCompare(a.eventDate || '');
    if (sortOrder === 'eventDate-asc') return (a.eventDate || '').localeCompare(b.eventDate || '');
    if (sortOrder === 'updatedAt-desc') return (b.updatedAt || '').localeCompare(a.updatedAt || '');
    if (sortOrder === 'name-asc') return (a.name || '').localeCompare(b.name || '');
    return 0;
  });

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const safePage = Math.min(page, Math.max(1, totalPages));
  const paged = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);

  const toggleSelect = (id) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const selectAll = () => {
    if (selectedIds.size === filtered.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filtered.map((i) => i.id)));
    }
  };

  const exitSelectMode = () => {
    setSelectMode(false);
    setSelectedIds(new Set());
  };

  if (loading) {
    return (
      <div className="loading-overlay">
        <div className="loading-spinner-lg" />
      </div>
    );
  }

  // 空状態は下のreturn内で表示（月ナビを維持するため早期returnしない）

  const prevMonth = () => {
    setMonthFilterEnabled(true);
    setMonthCursor((c) => c.month === 0 ? { year: c.year - 1, month: 11 } : { year: c.year, month: c.month - 1 });
    onPageChange(1);
  };
  const nextMonth = () => {
    setMonthFilterEnabled(true);
    setMonthCursor((c) => c.month === 11 ? { year: c.year + 1, month: 0 } : { year: c.year, month: c.month + 1 });
    onPageChange(1);
  };
  const thisMonth = () => {
    setMonthFilterEnabled(true);
    const n = new Date();
    setMonthCursor({ year: n.getFullYear(), month: n.getMonth() });
    onPageChange(1);
  };

  return (
    <>
      {/* 月ナビゲーション（イベントタイプのみ） */}
      {type === 'event' && (
        <div style={{ padding: '0 24px 8px', display: 'flex', alignItems: 'center', gap: 8 }}>
          <button className="btn btn-sm btn-secondary" onClick={prevMonth}>‹ 前月</button>
          <button
            className="btn btn-sm"
            onClick={thisMonth}
            style={{
              fontSize: 13, fontWeight: 700,
              background: monthFilterEnabled ? '#ede9fe' : '#f3f4f6',
              color: monthFilterEnabled ? '#7c3aed' : '#6b7280',
              border: `1.5px solid ${monthFilterEnabled ? '#c4b5fd' : '#d1d5db'}`,
              padding: '6px 14px', minWidth: 120,
            }}
            title={monthFilterEnabled ? 'クリックで今月に戻る' : 'クリックで月フィルタを有効化'}
          >
            📅 {monthCursor.year}年{monthCursor.month + 1}月
          </button>
          <button className="btn btn-sm btn-secondary" onClick={nextMonth}>翌月 ›</button>
          {monthFilterEnabled && (
            <button
              className="btn btn-sm"
              onClick={() => { setMonthFilterEnabled(false); onPageChange(1); }}
              style={{ fontSize: 11, background: '#fee2e2', color: '#dc2626', border: '1px solid #fca5a5' }}
            >✕ 月フィルタ解除</button>
          )}
        </div>
      )}

      {/* 一括操作バー */}
      <div style={{ padding: '0 24px', marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '8px' }}>
        <button
          className="btn btn-sm"
          onClick={() => selectMode ? exitSelectMode() : setSelectMode(true)}
          style={{
            fontSize: '12px',
            background: selectMode ? '#fee2e2' : '#f3f4f6',
            color: selectMode ? '#dc2626' : '#6b7280',
            border: `1px solid ${selectMode ? '#fca5a5' : '#d1d5db'}`,
          }}
        >
          {selectMode ? '✕ 選択解除' : '☑️ 一括選択'}
        </button>
        <button
          className="btn btn-sm"
          onClick={() => setAllTagsOpen(!allTagsOpen)}
          style={{
            fontSize: '12px',
            background: allTagsOpen ? '#fef3c7' : '#e0f2fe',
            color: allTagsOpen ? '#d97706' : '#0369a1',
            border: `1px solid ${allTagsOpen ? '#fcd34d' : '#7dd3fc'}`,
          }}
        >
          {allTagsOpen ? '▼ タグ一括閉じ' : '▶ タグ一括開き'}
        </button>
        {selectedFolder === 'Gitレビュー' && onScanGithub && (
          <button
            className="btn btn-sm"
            onClick={onScanGithub}
            style={{ fontSize: '12px', background: '#f0fdf4', color: '#16a34a', border: '1px solid #bbf7d0', fontWeight: 600 }}
          >
            🔍 GitHubスキャン
          </button>
        )}

        {/* 一括参加者同期ボタン（全ユーザー表示） */}
        <button
          className="btn btn-sm"
          onClick={async () => {
            const eventItems = filtered.filter(i => i.item_type === 'event');
            if (eventItems.length === 0) { showToast?.('イベントがありません', 'info'); return; }
            showToast?.(`🔄 ${eventItems.length}件の参加者を一括同期中...`, 'info');
            let ok = 0, ng = 0;
            for (const item of eventItems) {
              try { await syncParticipants(item.id); ok++; } catch { ng++; }
            }
            showToast?.(`参加者同期完了（成功:${ok} / 失敗:${ng}）`, ok > 0 ? 'success' : 'error');
            // データ再読み込みはshowToast後にユーザーが手動リロード
          }}
          style={{ fontSize: '12px', background: '#ecfdf5', color: '#059669', border: '1px solid #6ee7b7', fontWeight: 600 }}
        >
          🔄 一括参加者同期
        </button>

        {selectMode && (
          <>
            <button
              className="btn btn-sm"
              onClick={selectAll}
              style={{ fontSize: '12px', background: '#eef2ff', color: '#4f46e5', border: '1px solid #c7d2fe' }}
            >
              {selectedIds.size === filtered.length ? '全解除' : '全選択'} ({selectedIds.size}/{filtered.length})
            </button>

            {selectedIds.size > 0 && (
              <>
                <button
                  className="btn btn-sm btn-danger"
                  onClick={() => onBulkDelete && onBulkDelete([...selectedIds], 'remote')}
                  style={{ fontSize: '12px' }}
                >
                  🗑️ ポータルも削除 ({selectedIds.size}件)
                </button>
                <button
                  className="btn btn-sm"
                  onClick={() => onBulkDelete && onBulkDelete([...selectedIds], 'local')}
                  style={{ fontSize: '12px', background: '#f3f4f6', color: '#6b7280', border: '1px solid #d1d5db' }}
                >
                  📂 ローカルのみ削除 ({selectedIds.size}件)
                </button>
              </>
            )}
          </>
        )}
      </div>

      <div className="item-list-container">
        {filtered.length === 0 && (
          <div className="item-list-empty">
            <div className="item-list-empty-icon">📝</div>
            <div className="item-list-empty-text">
              {monthFilterEnabled
                ? `${monthCursor.year}年${monthCursor.month + 1}月のイベントはありません`
                : 'テキストがありません'}
            </div>
            <div className="item-list-empty-sub">
              {monthFilterEnabled
                ? '前後の月に移動するか、月フィルタを解除してください'
                : selectedFolder
                ? 'このフォルダにはテキストがありません'
                : '「新規作成」ボタンからテキストを追加してください'}
            </div>
          </div>
        )}
        <div className="item-grid">
          {paged.map((item) => (
            <div key={item.id} style={{ position: 'relative' }}>
              {selectMode && (
                <div
                  onClick={() => toggleSelect(item.id)}
                  style={{
                    position: 'absolute', top: '8px', left: '8px', zIndex: 10,
                    width: '22px', height: '22px', borderRadius: '4px', cursor: 'pointer',
                    background: selectedIds.has(item.id) ? '#4f46e5' : '#fff',
                    border: `2px solid ${selectedIds.has(item.id) ? '#4f46e5' : '#d1d5db'}`,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: '#fff', fontSize: '14px', fontWeight: 700,
                  }}
                >
                  {selectedIds.has(item.id) ? '✓' : ''}
                </div>
              )}
              <ItemCard
                item={item}
                type={type}
                folders={folders}
                onEdit={onEdit}
                onDelete={onDelete}
                onPost={onPost}
                onDuplicate={onDuplicate}
                onCancel={onCancel}
                onRefresh={onRefresh}
                showToast={showToast}
                tagsOpen={allTagsOpen}
                userRole={userRole}
              />
            </div>
          ))}
        </div>
      </div>
      <Pagination
        page={safePage}
        totalPages={totalPages}
        totalItems={filtered.length}
        onPageChange={onPageChange}
      />
    </>
  );
}
