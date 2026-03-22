import { useState, useCallback } from 'react';
import { renameFolder, deleteFolder } from '../api.js';

// Compute item counts per folder path
function buildFolderCounts(items) {
  const counts = {};
  items.forEach((item) => {
    const f = item.folder || '';
    if (f) {
      counts[f] = (counts[f] || 0) + 1;
      // Also count for parent path
      if (f.includes('/')) {
        const parent = f.split('/')[0];
        counts[parent] = (counts[parent] || 0) + 1;
      }
    }
  });
  return counts;
}

function FolderRow({ folderPath, label, isActive, onClick, count, onRename, onDelete, depth = 0 }) {
  const [editing, setEditing] = useState(false);
  const [editValue, setEditValue] = useState(label);

  function handleEditConfirm() {
    const trimmed = editValue.trim();
    if (trimmed && trimmed !== label) {
      if (trimmed.includes('/')) {
        alert('フォルダ名にスラッシュは使えません');
        return;
      }
      onRename(folderPath, trimmed);
    }
    setEditing(false);
  }

  function handleEditKeyDown(e) {
    if (e.key === 'Enter') handleEditConfirm();
    if (e.key === 'Escape') { setEditing(false); setEditValue(label); }
  }

  if (editing) {
    return (
      <div className="folder-edit-row">
        <input
          className="folder-edit-input"
          value={editValue}
          onChange={(e) => setEditValue(e.target.value)}
          onKeyDown={handleEditKeyDown}
          autoFocus
        />
        <button className="folder-edit-confirm" onClick={handleEditConfirm}>OK</button>
        <button className="folder-edit-cancel" onClick={() => { setEditing(false); setEditValue(label); }}>取消</button>
      </div>
    );
  }

  return (
    <div className="folder-row" style={depth > 0 ? { paddingLeft: '24px' } : {}}>
      <button
        className={`folder-btn ${isActive ? 'active' : ''}`}
        onClick={onClick}
      >
        <span className="folder-icon">{depth > 0 ? '📂' : '📁'}</span>
        <span className="folder-name-text">{label}</span>
        {count > 0 && <span className="folder-count">{count}</span>}
      </button>
      <div className="folder-actions">
        <button
          className="folder-action-btn"
          title="リネーム"
          onClick={(e) => { e.stopPropagation(); setEditing(true); setEditValue(label); }}
        >✏</button>
        <button
          className="folder-action-btn delete"
          title="削除"
          onClick={(e) => { e.stopPropagation(); onDelete(folderPath); }}
        >×</button>
      </div>
    </div>
  );
}

export default function FolderList({ type, folders, items, selectedFolder, onSelectFolder, onFolderChange, showToast }) {
  const folderCounts = buildFolderCounts(items);
  const totalCount = items.length;

  const handleRename = useCallback(async (path, newName) => {
    try {
      await renameFolder(type, { path, newName });
      await onFolderChange();
      showToast('フォルダ名を変更しました', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    }
  }, [type, onFolderChange, showToast]);

  const handleDelete = useCallback(async (path) => {
    if (!window.confirm(`「${path}」フォルダを削除しますか？\nアイテムは未分類に移動されます。`)) return;
    try {
      await deleteFolder(type, path);
      await onFolderChange();
      if (selectedFolder === path || (selectedFolder || '').startsWith(path + '/')) {
        onSelectFolder(null);
      }
      showToast('フォルダを削除しました', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    }
  }, [type, onFolderChange, selectedFolder, onSelectFolder, showToast]);

  return (
    <>
      <button
        className={`folder-all-btn ${!selectedFolder ? 'active' : ''}`}
        onClick={() => onSelectFolder(null)}
      >
        <span>すべて</span>
        <span className="folder-count">{totalCount}</span>
      </button>

      {folders.map((parent) => (
        <div key={parent.name} className="folder-item">
          <FolderRow
            folderPath={parent.name}
            label={parent.name}
            isActive={selectedFolder === parent.name}
            onClick={() => onSelectFolder(parent.name)}
            count={folderCounts[parent.name] || 0}
            onRename={handleRename}
            onDelete={handleDelete}
            depth={0}
          />
          {parent.children && parent.children.length > 0 && (
            <div className="folder-children">
              {parent.children.map((child) => {
                const childPath = `${parent.name}/${child}`;
                return (
                  <FolderRow
                    key={childPath}
                    folderPath={childPath}
                    label={child}
                    isActive={selectedFolder === childPath}
                    onClick={() => onSelectFolder(childPath)}
                    count={folderCounts[childPath] || 0}
                    onRename={handleRename}
                    onDelete={handleDelete}
                    depth={1}
                  />
                );
              })}
            </div>
          )}
        </div>
      ))}
    </>
  );
}
