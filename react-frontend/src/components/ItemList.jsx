import { useState } from 'react';
import ItemCard from './ItemCard.jsx';

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
  onScanGithub,
  userRole = 'admin',
}) {
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [selectMode, setSelectMode] = useState(false);
  const [allTagsOpen, setAllTagsOpen] = useState(true);

  // Filter items by selected folder + search query
  // 親フォルダ選択時は子フォルダのアイテムも含める（前方一致）
  let filtered = selectedFolder
    ? items.filter((item) => {
        const f = item.folder || '';
        return f === selectedFolder || f.startsWith(selectedFolder + '/');
      })
    : items;

  if (searchQuery.trim()) {
    const q = searchQuery.trim().toLowerCase();
    filtered = filtered.filter((item) =>
      (item.name || '').toLowerCase().includes(q) ||
      (item.content || '').toLowerCase().includes(q) ||
      (item.eventDate || '').includes(q) ||
      (item.folder || '').toLowerCase().includes(q)
    );
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

  if (filtered.length === 0) {
    return (
      <div className="item-list-container">
        <div className="item-list-empty">
          <div className="item-list-empty-icon">📝</div>
          <div className="item-list-empty-text">テキストがありません</div>
          <div className="item-list-empty-sub">
            {selectedFolder
              ? 'このフォルダにはテキストがありません'
              : '「新規作成」ボタンからテキストを追加してください'}
          </div>
        </div>
      </div>
    );
  }

  return (
    <>
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
