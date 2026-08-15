import { useState, useCallback } from 'react';
import FolderList from './FolderList.jsx';
import { createFolder } from '../api.js';

export default function Sidebar({
  activeType,
  onTypeChange,
  folders,
  items,
  selectedFolder,
  onSelectFolder,
  onFolderChange,
  showToast,
  onNavigate,
}) {
  const [showAddFolder, setShowAddFolder] = useState(false);
  const [newFolderParent, setNewFolderParent] = useState('');
  const [newFolderName, setNewFolderName] = useState('');
  const [adding, setAdding] = useState(false);

  const handleAddFolder = useCallback(async () => {
    if (!newFolderName.trim()) {
      showToast('フォルダ名を入力してください', 'error');
      return;
    }
    if (newFolderName.includes('/')) {
      showToast('フォルダ名にスラッシュは使えません', 'error');
      return;
    }
    setAdding(true);
    try {
      await createFolder(activeType, {
        name: newFolderName.trim(),
        parent: newFolderParent || undefined,
      });
      await onFolderChange();
      setNewFolderName('');
      setNewFolderParent('');
      setShowAddFolder(false);
      showToast('フォルダを作成しました', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setAdding(false);
    }
  }, [activeType, newFolderName, newFolderParent, onFolderChange, showToast]);

  return (
    <aside className="sidebar">
      <div className="sidebar-header">
        <p className="sidebar-title" onClick={() => { onSelectFolder(null); onTypeChange('event'); onNavigate?.('main'); }} style={{ cursor: 'pointer' }}>イベント管理</p>
        <div className="type-tabs">
          <button
            className={`type-tab ${activeType === 'event' ? 'active' : ''}`}
            onClick={() => { onTypeChange('event'); onNavigate?.('main'); }}
          >
            イベント
          </button>
          <button
            className={`type-tab ${activeType === 'student' ? 'active' : ''}`}
            onClick={() => { onTypeChange('student'); onNavigate?.('main'); }}
          >
            受講生サポート
          </button>
        </div>
        <div className="page-nav">
          <button
            className="type-tab"
            onClick={() => onNavigate?.('students')}
            title="受講生一覧ページへ"
          >
            🎓 受講生管理
          </button>
          <button
            className="type-tab"
            onClick={() => onNavigate?.('x')}
            title="X 自動投稿ページへ"
          >
            𝕏 X 管理
          </button>
          <button
            className="type-tab"
            onClick={() => onNavigate?.('meetingNotifications')}
            title="定例ミーティング通知ページへ"
          >
            📅 定例通知
          </button>
          <button
            className="type-tab"
            onClick={() => onNavigate?.('research')}
            title="交流会リサーチページへ"
          >
            🔎 リサーチ
          </button>
        </div>
      </div>

      <div className="sidebar-content">
        <p className="sidebar-section-label">フォルダ</p>

        <FolderList
          type={activeType}
          folders={folders}
          items={items}
          selectedFolder={selectedFolder}
          onSelectFolder={onSelectFolder}
          onFolderChange={onFolderChange}
          showToast={showToast}
        />
      </div>

      {/* Add Folder */}
      <div className="add-folder-section">
        {!showAddFolder ? (
          <button
            className="add-folder-toggle"
            onClick={() => setShowAddFolder(true)}
          >
            + フォルダを追加
          </button>
        ) : (
          <div className="add-folder-form">
            <select
              className="add-folder-select"
              value={newFolderParent}
              onChange={(e) => setNewFolderParent(e.target.value)}
            >
              <option value="">-- 親フォルダなし (ルート) --</option>
              {folders.map((f) => (
                <option key={f.name} value={f.name}>{f.name}</option>
              ))}
            </select>
            <input
              className="add-folder-input"
              placeholder="フォルダ名"
              value={newFolderName}
              onChange={(e) => setNewFolderName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleAddFolder();
                if (e.key === 'Escape') { setShowAddFolder(false); setNewFolderName(''); setNewFolderParent(''); }
              }}
              autoFocus
            />
            <button
              className="add-folder-submit"
              onClick={handleAddFolder}
              disabled={adding}
            >
              {adding ? '作成中...' : '追加'}
            </button>
            <button
              style={{ padding: '5px', background: 'none', border: 'none', cursor: 'pointer', color: '#9878cc', fontSize: '12px' }}
              onClick={() => { setShowAddFolder(false); setNewFolderName(''); setNewFolderParent(''); }}
            >
              キャンセル
            </button>
          </div>
        )}
      </div>

    </aside>
  );
}
