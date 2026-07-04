import { useState, useEffect, useCallback, useRef } from 'react';
import Sidebar from './components/Sidebar.jsx';
import ItemList from './components/ItemList.jsx';
import PostModal from './components/PostModal.jsx';
import ConnectionsPage from './components/ConnectionsPage.jsx';
import CalendarView from './components/CalendarView.jsx';
import LoginPage from './components/LoginPage.jsx';
import StudentsPage from './components/StudentsPage.jsx';
import UsersPage from './components/UsersPage.jsx';
import DetailModal from './components/DetailModal.jsx';
import XPage from './components/x/XPage.jsx';
import AnnouncementPanel from './components/AnnouncementPanel.jsx';
import { fetchTexts, fetchFolders, deleteText, createText, deleteRemoteEvents, cancelRemoteEvents, fetchPostingHistory, scanGithubReviews } from './api.js';
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
  // 'main' | 'x' | 'announcements'
  // URL は使っていない（react-router 未導入）が、ヘッダーのリンクラベルとして /x, /announcements を使う。
  const [activePage, setActivePage] = useState('main');
  const [activeType, setActiveType] = useState('event');
  const [items, setItems] = useState([]);
  const [folders, setFolders] = useState([]);
  const [loadingItems, setLoadingItems] = useState(false);
  const [selectedFolder, setSelectedFolder] = useState(null);
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState('upcoming'); // 'upcoming' | 'ended' | 'all'

  // Modals
  const [editItem, setEditItem] = useState(null); // null = closed, {} = new, item = edit
  const [postItem, setPostItem] = useState(null);
  const [deleteConfirm, setDeleteConfirm] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortOrder, setSortOrder] = useState('eventDate-desc');
  const [showConnections, setShowConnections] = useState(false);
  const [showCalendar, setShowCalendar] = useState(true);
  const [showStudents, setShowStudents] = useState(false);
  const [showUsers, setShowUsers] = useState(false);
  const [detailItem, setDetailItem] = useState(null); // viewer用詳細モーダル
  const [currentUser, setCurrentUser] = useState(undefined); // undefined=loading, null=guest, object=logged in
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);

  // クリック外しでメニュー閉じる
  useEffect(() => {
    if (!menuOpen) return undefined;
    const handler = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) setMenuOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [menuOpen]);

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
  const loadAllRef = useRef(loadAll);
  loadAllRef.current = loadAll;

  useEffect(() => {
    let cancelled = false;
    const restoreSession = async () => {
      // OAuth callback から戻ってきた場合は ?token=xxx を session に交換してから current_user を取る
      const params = new URLSearchParams(window.location.search);
      const oauthToken = params.get('login') === 'success' ? params.get('token') : null;
      if (params.get('login')) {
        window.history.replaceState({}, '', window.location.pathname);
      }
      if (oauthToken) {
        try {
          await fetch('/api/sessions/exchange', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token: oauthToken }),
          });
        } catch {}
      }
      try {
        const res = await fetch('/api/current_user');
        const d = await res.json();
        if (!cancelled && d && d.id) {
          setCurrentUser(d);
          // viewer はカレンダー表示をデフォルトに（一覧切替は可能）
          if (d.role === 'viewer') {
            setShowCalendar(true);
            setShowConnections(false);
            setShowStudents(false);
          }
          // セッション復元後に即座にデータ取得（2回呼んで確実に）
          await loadAllRef.current();
          // 少し待ってからもう一度（レンダリング完了後のデータ反映保証）
          setTimeout(() => { if (!cancelled) loadAllRef.current(); }, 500);
        }
      } catch {}
    };
    restoreSession();
    return () => { cancelled = true; };
  }, []);

  // Load when type changes or user becomes authenticated
  const activeTypeRef = useRef(activeType);
  useEffect(() => {
    activeTypeRef.current = activeType;
    setSelectedFolder(null);
    setPage(1);
  }, [activeType]);

  useEffect(() => {
    if (!currentUser) return;
    loadAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeType, currentUser?.id]);

  // ===== Folder change =====
  function handleSelectFolder(folder) {
    setSelectedFolder(folder);
    setSearchQuery('');
    setPage(1);
    setStatusFilter('all'); // フォルダ内の全イベントを表示（終了含む）
    setShowConnections(false);
    setShowStudents(false);
    setShowCalendar(false);
  }

  // ===== Delete =====
  const [deleteRemoteRunning, setDeleteRemoteRunning] = useState(false);
  const [deleteRemoteLogs, setDeleteRemoteLogs] = useState([]);
  const [cancelRunning, setCancelRunning] = useState(false);
  const [cancelLogs, setCancelLogs] = useState([]);

  // ローカルのみ削除
  async function handleDeleteLocalOnly() {
    if (!deleteConfirm) return;
    try {
      await deleteText(activeType, deleteConfirm.id);
      showToast('削除しました（ローカルのみ）', 'success');
      setDeleteConfirm(null);
      await loadItems();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  // ポータルサイトも含めて削除
  async function handleDeleteWithRemote() {
    if (!deleteConfirm) return;
    setDeleteRemoteRunning(true);
    setDeleteRemoteLogs([]);
    try {
      await deleteRemoteEvents(deleteConfirm.id, (event) => {
        if (event.type === 'log' || event.type === 'error') {
          setDeleteRemoteLogs((prev) => [...prev, event.message]);
        }
      });
      // リモート削除完了後にローカルも削除
      await deleteText(activeType, deleteConfirm.id);
      showToast('全サイトから削除しました', 'success');
      setDeleteConfirm(null);
      setDeleteRemoteLogs([]);
      await loadItems();
    } catch (err) {
      showToast(`削除エラー: ${err.message}`, 'error');
    } finally {
      setDeleteRemoteRunning(false);
    }
  }

  // 一斉中止
  async function handleCancelAll(item) {
    setCancelRunning(true);
    setCancelLogs([]);
    try {
      await cancelRemoteEvents(item.id, (event) => {
        if (event.type === 'log' || event.type === 'error') {
          setCancelLogs((prev) => [...prev, event.message]);
        }
      });
      showToast('全サイトのイベントを中止しました', 'success');
      setCancelLogs([]);
    } catch (err) {
      showToast(`中止エラー: ${err.message}`, 'error');
    } finally {
      setCancelRunning(false);
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

  // ===== Bulk Delete =====
  async function handleBulkDelete(ids, mode) {
    if (!ids.length) return;
    const label = mode === 'remote' ? 'ポータルサイトも含めて' : 'ローカルのみ';
    if (!confirm(`${ids.length}件を${label}削除しますか？`)) return;

    for (const id of ids) {
      try {
        if (mode === 'remote') {
          try {
            await deleteRemoteEvents(id, () => {});
          } catch (_) {}
        }
        await deleteText(activeType, id);
      } catch (err) {
        showToast(`${id}: ${err.message}`, 'error');
      }
    }
    showToast(`${ids.length}件を削除しました`, 'success');
    await loadItems();
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
        if (user) {
          setCurrentUser(user);
          // ログイン直後に即座にデータ取得（useEffectの発火を待たず確実に実行）
          loadAll();
        }
      }} />
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
        onNavigate={(target) => {
          if (target === 'students') {
            setActivePage('main');
            setShowStudents(true);
            setShowCalendar(false);
            setShowConnections(false);
          } else {
            setActivePage(target);
          }
        }}
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
              <div ref={menuRef} style={{ position: 'relative' }}>
                <button
                  type="button"
                  onClick={() => setMenuOpen((v) => !v)}
                  style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '4px 12px', background: '#f0fdf4', borderRadius: '8px', border: '1px solid #bbf7d0', cursor: 'pointer' }}
                >
                  {currentUser.avatarUrl && (
                    <img src={currentUser.avatarUrl} alt="" style={{ width: 24, height: 24, borderRadius: '50%' }} />
                  )}
                  <div style={{ lineHeight: 1.2, textAlign: 'left' }}>
                    <div style={{ fontSize: '12px', fontWeight: 600, color: '#166534' }}>{currentUser.name}</div>
                    <div style={{ fontSize: '10px', color: '#6b7280' }}>{currentUser.email}</div>
                  </div>
                  <span style={{ fontSize: '10px', color: '#166534', marginLeft: '2px' }}>{menuOpen ? '▲' : '▼'}</span>
                </button>

                {menuOpen && (
                  <div style={{ position: 'absolute', top: 'calc(100% + 6px)', right: 0, minWidth: '220px', background: '#fff', border: '1px solid #d1d5db', borderRadius: '8px', boxShadow: '0 8px 24px rgba(0,0,0,0.12)', padding: '6px 0', zIndex: 50 }}>
                    {(() => {
                      const sectionLabel = (text) => (
                        <div style={{ padding: '6px 14px 2px', fontSize: '10px', color: '#9ca3af', fontWeight: 600, letterSpacing: '0.04em' }}>{text}</div>
                      );
                      const item = ({ key, label, active, onClick, disabled, danger }) => (
                        <button
                          key={key}
                          type="button"
                          disabled={disabled}
                          onClick={() => { onClick(); setMenuOpen(false); }}
                          style={{
                            width: '100%', textAlign: 'left', padding: '8px 14px', background: active ? '#f3f4f6' : 'transparent',
                            border: 'none', fontSize: '13px', color: danger ? '#dc2626' : (active ? '#111827' : '#374151'),
                            cursor: disabled ? 'not-allowed' : 'pointer', opacity: disabled ? 0.5 : 1, fontWeight: active ? 600 : 400,
                          }}
                        >{label}</button>
                      );
                      return (
                        <>
                          {sectionLabel('ページ')}
                          {item({ key: 'main', label: 'イベント一覧', active: activePage === 'main' && !showStudents && !showConnections && !showUsers, onClick: () => { setActivePage('main'); setShowStudents(false); setShowConnections(false); setShowUsers(false); } })}
                          {item({ key: 'ann', label: '告知', active: activePage === 'announcements', onClick: () => setActivePage('announcements') })}
                          {item({ key: 'x',   label: '𝕏 自動', active: activePage === 'x', onClick: () => setActivePage('x') })}

                          {sectionLabel('表示')}
                          {item({ key: 'cal', label: showCalendar ? '📋 一覧で見る' : '📅 カレンダーで見る', active: activePage === 'main' && showCalendar, onClick: () => { setActivePage('main'); setShowCalendar(!showCalendar); setShowConnections(false); setShowStudents(false); setShowUsers(false); } })}
                          {item({ key: 'stu', label: '🎓 受講生一覧',  active: activePage === 'main' && showStudents, onClick: () => { setActivePage('main'); setShowStudents(!showStudents); setShowCalendar(false); setShowConnections(false); setShowUsers(false); } })}

                          {currentUser?.role !== 'viewer' && (
                            <>
                              {sectionLabel('管理')}
                              {item({ key: 'conn', label: '🔗 サービス接続管理', active: activePage === 'main' && showConnections, onClick: () => { setActivePage('main'); setShowConnections(!showConnections); setShowCalendar(false); setShowStudents(false); setShowUsers(false); } })}
                              {currentUser?.role === 'admin' && item({ key: 'usr', label: '👥 ユーザー管理', active: activePage === 'main' && showUsers, onClick: () => { setActivePage('main'); setShowUsers(!showUsers); setShowCalendar(false); setShowConnections(false); setShowStudents(false); } })}
                            </>
                          )}

                          <div style={{ borderTop: '1px solid #e5e7eb', margin: '6px 0' }} />
                          {item({ key: 'logout', label: 'ログアウト', danger: true, onClick: async () => {
                            await fetch('/api/logout', { method: 'DELETE' });
                            setCurrentUser(null);
                          } })}
                        </>
                      );
                    })()}
                  </div>
                )}
              </div>
            )}
            {activePage === 'main' && currentUser?.role !== 'viewer' && (
              <button
                className="btn btn-primary"
                onClick={() => setEditItem({})}
              >
                + 新規作成
              </button>
            )}
          </div>
        </div>

        {/* ===== /x ページ ===== */}
        {activePage === 'x' && (
          <XPage showToast={showToast} />
        )}

        {/* ===== /announcements ページ ===== */}
        {activePage === 'announcements' && (
          <AnnouncementPanel showToast={showToast} />
        )}

        {/* Service Connections (toggle) */}
        {activePage === 'main' && showConnections && (
          <div style={{ padding: '0 24px', marginBottom: '16px' }}>
            <div style={{ borderRadius: '12px', border: '1.5px solid #e2d9f3', background: '#faf8ff', padding: '16px' }}>
              <ConnectionsPage
                showToast={showToast}
                onBack={() => setShowConnections(false)}
                onGoToList={() => setShowConnections(false)}
                inline
              />
            </div>
          </div>
        )}

        {/* Users Page (admin only) */}
        {activePage === 'main' && showUsers && currentUser?.role === 'admin' && (
          <UsersPage showToast={showToast} />
        )}

        {/* Students Page */}
        {activePage === 'main' && showStudents && (
          <StudentsPage showToast={showToast} />
        )}

        {/* Calendar View */}
        {activePage === 'main' && showCalendar && (
          <CalendarView
            items={items}
            selectedFolder={selectedFolder}
            statusFilter={statusFilter}
            onStatusFilterChange={setStatusFilter}
            userRole={currentUser?.role}
            onEditItem={(item) => currentUser?.role === 'viewer' ? setDetailItem(item) : setEditItem(item)}
            onShowInList={(item) => {
              setShowCalendar(false);
              if (item.folder) setSelectedFolder(item.folder);
              setSearchQuery(item.name || '');
              setPage(1);
            }}
            onNewEvent={(date) => {
              setActiveType('event');
              setShowCalendar(false);
              setEditItem({ eventDate: date });
            }}
            onNewStudent={(date) => {
              setActiveType('student');
              setShowCalendar(false);
              setEditItem({ eventDate: date });
            }}
            showToast={showToast}
          />
        )}

        {/* Search + Sort + Item List (接続管理・カレンダー表示中は非表示) */}
        {activePage === 'main' && !showConnections && !showCalendar && !showStudents && !showUsers && (<>
        <div className="search-bar">
          <span className="search-icon">🔍</span>
          <input
            className="search-input"
            type="text"
            value={searchQuery}
            onChange={(e) => { setSearchQuery(e.target.value); setPage(1); }}
            placeholder="タイトル・内容・日付で検索（終了/募集中でフィルタ）..."
          />
          {searchQuery && (
            <button
              className="search-clear"
              onClick={() => { setSearchQuery(''); setPage(1); }}
            >
              ✕
            </button>
          )}
          <div className="status-filter" role="tablist" aria-label="ステータス">
            <button
              className={`${statusFilter === 'upcoming' ? 'active upcoming' : ''}`}
              onClick={() => { setStatusFilter('upcoming'); setPage(1); }}
              title="開催前のイベントのみ"
            >🟢 募集中</button>
            <button
              className={`${statusFilter === 'ended' ? 'active ended' : ''}`}
              onClick={() => { setStatusFilter('ended'); setPage(1); }}
              title="終了済みイベントのみ"
            >🔴 終了</button>
            <button
              className={`${statusFilter === 'all' ? 'active' : ''}`}
              onClick={() => { setStatusFilter('all'); setPage(1); }}
              title="すべて表示"
            >すべて</button>
          </div>
          <select
            className="sort-select"
            value={sortOrder}
            onChange={(e) => { setSortOrder(e.target.value); setPage(1); }}
          >
            <option value="eventDate-desc">📅 開催日（新しい順）</option>
            <option value="eventDate-asc">📅 開催日（古い順）</option>
            <option value="updatedAt-desc">🕐 更新日（新しい順）</option>
            <option value="name-asc">🔤 名前順</option>
          </select>
        </div>

        <ItemList
          items={items}
          loading={loadingItems}
          type={activeType}
          folders={folders}
          selectedFolder={selectedFolder}
          searchQuery={searchQuery}
          sortOrder={sortOrder}
          statusFilter={statusFilter}
          onEdit={(item) => currentUser?.role === 'viewer' ? setDetailItem(item) : setEditItem(item)}
          onDelete={(item) => setDeleteConfirm(item)}
          onBulkDelete={handleBulkDelete}
          onPost={(item) => setPostItem(item)}
          onDuplicate={handleDuplicate}
          onCancel={handleCancelAll}
          onRefresh={loadItems}
          showToast={showToast}
          userRole={currentUser?.role}
          page={page}
          onPageChange={setPage}
          onScanGithub={async () => {
            showToast('🔍 GitHubスキャン開始...', 'info');
            try {
              await scanGithubReviews((event) => {
                if (event.type === 'log') showToast(event.message, 'info');
                else if (event.type === 'done') { showToast(event.message, 'success'); loadAll(); }
                else if (event.type === 'error') showToast(event.message, 'error');
              });
            } catch (e) { showToast(e.message, 'error'); }
          }}
        />
        </>)}
      </div>

      {/* Edit / Create / Post — 統合モーダル */}
      {editItem !== null && (
        <PostModal
          item={editItem && editItem.id ? editItem : null}
          folders={folders}
          activeType={activeType}
          onClose={() => setEditItem(null)}
          onSaved={loadAll}
          showToast={showToast}
        />
      )}
      {postItem && !editItem && (
        <PostModal
          item={postItem}
          folders={folders}
          activeType={activeType}
          onClose={() => setPostItem(null)}
          onSaved={loadAll}
          showToast={showToast}
        />
      )}

      {/* Delete Confirm Dialog */}
      {deleteConfirm && (
        <div
          className="modal-overlay"
          onClick={(e) => { if (e.target === e.currentTarget && !deleteRemoteRunning) setDeleteConfirm(null); }}
        >
          <div className="modal" style={{ maxWidth: '500px' }}>
            <div className="modal-header">
              <h2 className="modal-title">削除の確認</h2>
              <button className="modal-close" onClick={() => !deleteRemoteRunning && setDeleteConfirm(null)}>✕</button>
            </div>
            <div className="modal-body">
              <p className="confirm-message">
                「{deleteConfirm.name}」を削除しますか？
              </p>
              <p style={{ fontSize: '13px', color: '#666', marginTop: '8px' }}>
                連携されているポータルサイトのイベントも同時に削除できます。
              </p>
              {deleteRemoteLogs.length > 0 && (
                <div style={{ background: '#1a1a2e', color: '#e0e0e0', borderRadius: '6px', padding: '10px', marginTop: '12px', maxHeight: '200px', overflowY: 'auto', fontSize: '12px', fontFamily: 'monospace' }}>
                  {deleteRemoteLogs.map((msg, i) => (
                    <div key={i} style={{ padding: '2px 0' }}>{msg}</div>
                  ))}
                </div>
              )}
            </div>
            <div className="modal-footer" style={{ flexDirection: 'column', gap: '8px' }}>
              <div style={{ display: 'flex', gap: '8px', width: '100%' }}>
                <button
                  className="btn btn-danger"
                  style={{ flex: 1 }}
                  onClick={handleDeleteWithRemote}
                  disabled={deleteRemoteRunning}
                >
                  {deleteRemoteRunning ? '削除中...' : 'ポータルサイトも削除'}
                </button>
                <button
                  className="btn btn-secondary"
                  style={{ flex: 1 }}
                  onClick={handleDeleteLocalOnly}
                  disabled={deleteRemoteRunning}
                >
                  ローカルのみ削除
                </button>
              </div>
              <button
                className="btn btn-secondary"
                style={{ width: '100%' }}
                onClick={() => setDeleteConfirm(null)}
                disabled={deleteRemoteRunning}
              >
                キャンセル
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Cancel All Dialog */}
      {cancelRunning && (
        <div className="modal-overlay">
          <div className="modal" style={{ maxWidth: '500px' }}>
            <div className="modal-header">
              <h2 className="modal-title">一斉中止処理中...</h2>
            </div>
            <div className="modal-body">
              <div style={{ background: '#1a1a2e', color: '#e0e0e0', borderRadius: '6px', padding: '10px', maxHeight: '300px', overflowY: 'auto', fontSize: '12px', fontFamily: 'monospace' }}>
                {cancelLogs.map((msg, i) => (
                  <div key={i} style={{ padding: '2px 0' }}>{msg}</div>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Detail Modal (viewer用) */}
      {detailItem && (
        <DetailModal item={detailItem} onClose={() => setDetailItem(null)} />
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
