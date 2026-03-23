import { useState, useEffect, useCallback, useRef } from 'react';
import Sidebar from './components/Sidebar.jsx';
import ItemList from './components/ItemList.jsx';
import EditModal from './components/EditModal.jsx';
import PostModal from './components/PostModal.jsx';
import ConnectionsPage from './components/ConnectionsPage.jsx';
import LoginPage from './components/LoginPage.jsx';
import { fetchTexts, fetchFolders, deleteText, createText } from './api.js';
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
  const [activePage, setActivePage] = useState('main'); // 'main' | 'connections'
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
  const [currentUser, setCurrentUser] = useState(undefined); // undefined=loading, null=guest, object=logged in

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

  // Load current user on mount
  useEffect(() => {
    fetch('/api/current_user').then(r => r.json()).then(d => {
      if (d && d.id) setCurrentUser(d);
    }).catch(() => {});
    // URLにlogin=successがあればユーザー再取得してトップへ
    const params = new URLSearchParams(window.location.search);
    if (params.get('login') === 'success') {
      window.history.replaceState({}, '', window.location.pathname);
      fetch('/api/current_user').then(r => r.json()).then(d => {
        if (d && d.id) setCurrentUser(d);
      }).catch(() => {});
    }
  }, []);

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

  // ===== Duplicate =====
  async function handleDuplicate(item) {
    try {
      await createText(activeType, {
        name: `${item.name}（コピー）`,
        content: item.content,
        folder: item.folder || '',
      });
      showToast('複製しました', 'success');
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

  // ログイン画面（未認証時は必ず表示）
  if (!currentUser) {
    return (
      <LoginPage onLogin={(user) => {
        if (user) setCurrentUser(user);
      }} />
    );
  }

  if (activePage === 'connections') {
    return (
      <div className="app-shell" style={{ justifyContent: 'center' }}>
        <ConnectionsPage
          showToast={showToast}
          onBack={() => setActivePage('main')}
        />
        <div className="toast-container">
          {toasts.map((toast) => (
            <div key={toast.id} className={`toast ${toast.type}`} onClick={() => removeToast(toast.id)} style={{ cursor: 'pointer' }}>
              {toast.message}
            </div>
          ))}
        </div>
      </div>
    );
  }

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
        onNavigate={setActivePage}
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
            {currentUser && (
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginRight: '8px', padding: '4px 12px', background: '#f0fdf4', borderRadius: '8px', border: '1px solid #bbf7d0' }}>
                {currentUser.avatarUrl && (
                  <img src={currentUser.avatarUrl} alt="" style={{ width: 24, height: 24, borderRadius: '50%' }} />
                )}
                <div style={{ lineHeight: 1.2 }}>
                  <div style={{ fontSize: '12px', fontWeight: 600, color: '#166534' }}>{currentUser.name}</div>
                  <div style={{ fontSize: '10px', color: '#6b7280' }}>{currentUser.email}</div>
                </div>
                <button
                  onClick={async () => {
                    await fetch('/api/logout', { method: 'DELETE' });
                    setCurrentUser(null);
                  }}
                  style={{ marginLeft: '4px', padding: '2px 8px', background: 'none', border: '1px solid #d1d5db', borderRadius: '4px', fontSize: '10px', color: '#6b7280', cursor: 'pointer' }}
                >
                  ログアウト
                </button>
              </div>
            )}
            <button
              className="btn"
              onClick={() => setActivePage('connections')}
              title="サービス接続管理"
              style={{ background: '#eef2ff', color: '#4f46e5', border: '1.5px solid #c7d2fe', fontWeight: 600 }}
            >
              🔗 接続管理
            </button>
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
          onDuplicate={handleDuplicate}
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
