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
  onPost,
  onDuplicate,
  onRefresh,
  showToast,
  page,
  onPageChange,
  searchQuery = '',
}) {
  // Filter items by selected folder + search query
  let filtered = selectedFolder
    ? items.filter((item) => (item.folder || '') === selectedFolder)
    : items;

  if (searchQuery.trim()) {
    const q = searchQuery.trim().toLowerCase();
    filtered = filtered.filter((item) =>
      (item.name || '').toLowerCase().includes(q) ||
      (item.content || '').toLowerCase().includes(q)
    );
  }

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const safePage = Math.min(page, Math.max(1, totalPages));
  const paged = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);

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
      <div className="item-list-container">
        <div className="item-grid">
          {paged.map((item) => (
            <ItemCard
              key={item.id}
              item={item}
              type={type}
              folders={folders}
              onEdit={onEdit}
              onDelete={onDelete}
              onPost={onPost}
              onDuplicate={onDuplicate}
              onRefresh={onRefresh}
              showToast={showToast}
            />
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
