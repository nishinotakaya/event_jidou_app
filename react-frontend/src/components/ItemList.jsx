import ItemCard from './ItemCard.jsx';

const PAGE_SIZE = 10;

function Pagination({ page, totalPages, onPageChange }) {
  if (totalPages <= 1) return null;

  const pages = [];
  for (let i = 1; i <= totalPages; i++) {
    pages.push(i);
  }

  // Truncate if many pages
  const renderPages = () => {
    if (totalPages <= 7) return pages.map(renderBtn);
    const items = [];
    if (page > 3) {
      items.push(renderBtn(1));
      if (page > 4) items.push(<span key="el1" className="pagination-ellipsis">…</span>);
    }
    const start = Math.max(1, page - 2);
    const end = Math.min(totalPages, page + 2);
    for (let i = start; i <= end; i++) items.push(renderBtn(i));
    if (page < totalPages - 2) {
      if (page < totalPages - 3) items.push(<span key="el2" className="pagination-ellipsis">…</span>);
      items.push(renderBtn(totalPages));
    }
    return items;
  };

  function renderBtn(i) {
    return (
      <button
        key={i}
        className={`pagination-btn ${i === page ? 'active' : ''}`}
        onClick={() => onPageChange(i)}
      >
        {i}
      </button>
    );
  }

  return (
    <div className="pagination">
      <button
        className="pagination-btn"
        onClick={() => onPageChange(page - 1)}
        disabled={page === 1}
      >
        ＜前
      </button>
      {renderPages()}
      <button
        className="pagination-btn"
        onClick={() => onPageChange(page + 1)}
        disabled={page === totalPages}
      >
        次＞
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
  onRefresh,
  showToast,
  page,
  onPageChange,
}) {
  // Filter items by selected folder
  const filtered = selectedFolder
    ? items.filter((item) => (item.folder || '') === selectedFolder)
    : items;

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
              onRefresh={onRefresh}
              showToast={showToast}
            />
          ))}
        </div>
      </div>
      <Pagination
        page={safePage}
        totalPages={totalPages}
        onPageChange={onPageChange}
      />
    </>
  );
}
