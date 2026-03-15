import { useState, useEffect, useCallback, useRef } from 'react';
import Sidebar from './components/Sidebar.jsx';
import ItemList from './components/ItemList.jsx';
import EditModal from './components/EditModal.jsx';
import PostModal from './components/PostModal.jsx';
import { fetchTexts, fetchFolders, deleteText } from './api.js';
import './index.css';

// ===== Toast Hook =====
function useToasts() {
  const [toasts, setToasts] = useState([]);
  const timerRef = useRef({});

  const showToast = useCallback((message, type = 'info') => {
    const id = Date.now() + Math.random();
    setToasts((prev) => [...prev, { id, message, type }]);
    timerRef.current[id] = setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, 3500);
  }, []);

  const removeToast = useCallback((id) => {
    clearTimeout(timerRef.current[id]);
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return { toasts, showToast, removeToast };
}

export default function App() {
  const [activeType, setActiveType] = useState('event');
  const [items, setItems] = useState([]);
  const [folders, setFolders] = useState([]);
  const [loadingItems, setLoadingItems] = useState(false);
  const [selectedFolder, setSelectedFolder] = useState(null);
  const [page, setPage] = useState(1);

  // Modals
  const [editItem, setEditItem] = useState(null); // null = closed, {} = new, item = edit
  const [postItem, setPostItem] = useState(null);
  const [deleteConfirm, setDeleteConfirm] = useState(null);

  const { toasts, showToast, removeToast } = useToasts();

  // ===== Load data =====
  const loadItems = useCallback(async () => {
    setLoadingItems(true);
    try {
      const data = await fetchTexts(activeType);
      // Sort by updatedAt desc
      data.sort((a, b) => ((b.updatedAt || '') > (a.updatedAt || '') ? 1 : -1));
      setItems(data);
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setLoadingItems(false);
    }
  }, [activeType, showToast]);

  const loadFolders = useCallback(async () => {
    try {
      const data = await fetchFolders(activeType);
      setFolders(data);
    } catch (err) {
      showToast(err.message, 'error');
    }
  }, [activeType, showToast]);

  const loadAll = useCallback(async () => {
    await Promise.all([loadItems(), loadFolders()]);
  }, [loadItems, loadFolders]);

  // Load when type changes
  const activeTypeRef = useRef(activeType);
  useEffect(() => {
    activeTypeRef.current = activeType;
    setSelectedFolder(null);
    setPage(1);
    loadAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeType]);

  // ===== Folder change =====
  function handleSelectFolder(folder) {
    setSelectedFolder(folder);
    setPage(1);
  }

  // ===== Delete =====
  async function handleDeleteConfirmed() {
    if (!deleteConfirm) return;
    try {
      await deleteText(activeType, deleteConfirm.id);
      showToast('削除しました', 'success');
      setDeleteConfirm(null);
      await loadItems();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  // ===== Labels =====
  const typeLabel = activeType === 'event' ? 'イベント告知' : '受講生サポート';

  const folderBreadcrumb = selectedFolder
    ? selectedFolder.includes('/')
      ? selectedFolder.split('/').join(' > ')
      : selectedFolder
    : 'すべて';

  return (
    <div className="app-shell">
      <Sidebar
        activeType={activeType}
        onTypeChange={setActiveType}
        folders={folders}
        items={items}
        selectedFolder={selectedFolder}
        onSelectFolder={handleSelectFolder}
        onFolderChange={loadAll}
        showToast={showToast}
      />

      <div className="main-area">
        {/* Header */}
        <div className="main-header">
          <div className="main-header-left">
            <h1 className="main-header-title">{typeLabel}</h1>
            <div className="folder-breadcrumb">
              <span className="folder-breadcrumb-sep">/</span>
              <span>{folderBreadcrumb}</span>
            </div>
          </div>
          <div className="main-header-actions">
            <button
              className="btn btn-secondary"
              onClick={loadAll}
              title="更新"
            >
              更新
            </button>
            <button
              className="btn btn-primary"
              onClick={() => setEditItem({})}
            >
              + 新規作成
            </button>
          </div>
        </div>

        {/* Item List */}
        <ItemList
          items={items}
          loading={loadingItems}
          type={activeType}
          folders={folders}
          selectedFolder={selectedFolder}
          onEdit={(item) => setEditItem(item)}
          onDelete={(item) => setDeleteConfirm(item)}
          onPost={(item) => setPostItem(item)}
          onRefresh={loadItems}
          showToast={showToast}
          page={page}
          onPageChange={setPage}
        />
      </div>

      {/* Edit / Create Modal */}
      {editItem !== null && (
        <EditModal
          item={editItem && editItem.id ? editItem : null}
          type={activeType}
          folders={folders}
          onClose={() => setEditItem(null)}
          onSaved={loadItems}
          showToast={showToast}
        />
      )}

      {/* Post Modal */}
      {postItem && (
        <PostModal
          item={postItem}
          onClose={() => setPostItem(null)}
          showToast={showToast}
        />
      )}

      {/* Delete Confirm Dialog */}
      {deleteConfirm && (
        <div
          className="modal-overlay"
          onClick={(e) => { if (e.target === e.currentTarget) setDeleteConfirm(null); }}
        >
          <div className="modal" style={{ maxWidth: '420px' }}>
            <div className="modal-header">
              <h2 className="modal-title">削除の確認</h2>
              <button className="modal-close" onClick={() => setDeleteConfirm(null)}>✕</button>
            </div>
            <div className="modal-body">
              <p className="confirm-message">
                「{deleteConfirm.name}」を削除しますか？
                <br />
                この操作は元に戻せません。
              </p>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setDeleteConfirm(null)}>
                キャンセル
              </button>
              <button className="btn btn-danger" onClick={handleDeleteConfirmed}>
                削除する
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toast Notifications */}
      <div className="toast-container">
        {toasts.map((toast) => (
          <div
            key={toast.id}
            className={`toast ${toast.type}`}
            onClick={() => removeToast(toast.id)}
            style={{ cursor: 'pointer' }}
          >
            {toast.message}
          </div>
        ))}
      </div>
    </div>
  );
}
