import { useState, useCallback } from 'react';
import { updateText } from '../api.js';

function buildFolderOptions(folders) {
  const opts = [{ value: '', label: '未分類' }];
  folders.forEach((parent) => {
    opts.push({ value: parent.name, label: parent.name });
    (parent.children || []).forEach((child) => {
      opts.push({ value: `${parent.name}/${child}`, label: `${parent.name} / ${child}` });
    });
  });
  return opts;
}

export default function ItemCard({ item, type, folders, onEdit, onDelete, onPost, onDuplicate, onRefresh, showToast }) {
  const [movingFolder, setMovingFolder] = useState(false);
  const folderOptions = buildFolderOptions(folders);

  const handleFolderMove = useCallback(async (newFolder) => {
    if (newFolder === item.folder) return;
    setMovingFolder(true);
    try {
      await updateText(type, item.id, {
        name: item.name,
        content: item.content,
        folder: newFolder,
      });
      await onRefresh();
      showToast('フォルダを移動しました', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setMovingFolder(false);
    }
  }, [type, item, onRefresh, showToast]);

  const folderLabel = item.folder
    ? item.folder.includes('/')
      ? item.folder.split('/').join(' / ')
      : item.folder
    : null;

  const createdAt = item.createdAt || '';
  const updatedAt = item.updatedAt || '';

  return (
    <div className="item-card">
      <div className="item-card-header">
        <div className="item-card-name">{item.name}</div>
        <div className="item-card-actions">
          <button
            className="btn btn-teal btn-sm"
            onClick={() => onPost(item)}
            title="投稿"
          >
            投稿
          </button>
          <button
            className="btn btn-secondary btn-sm"
            onClick={() => onEdit(item)}
            title="編集"
          >
            編集
          </button>
          <button
            className="btn btn-outline btn-sm"
            onClick={() => onDuplicate(item)}
            title="複製"
          >
            複製
          </button>
          <button
            className="btn btn-danger btn-sm"
            onClick={() => onDelete(item)}
            title="削除"
          >
            削除
          </button>
        </div>
      </div>

      {folderLabel && (
        <div>
          <span className="item-card-folder-badge">📁 {folderLabel}</span>
        </div>
      )}

      <div className="item-card-content">{item.content}</div>

      <div className="item-card-meta">
        <div className="item-card-dates">
          {createdAt && <span>作成: {createdAt}</span>}
          {updatedAt && updatedAt !== createdAt && <span> / 更新: {updatedAt}</span>}
        </div>
        <div className="item-card-folder-move">
          <select
            className="item-card-folder-select"
            value={item.folder || ''}
            onChange={(e) => handleFolderMove(e.target.value)}
            disabled={movingFolder}
            title="フォルダを移動"
          >
            {folderOptions.map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
          {movingFolder && <span className="spinner" />}
        </div>
      </div>
    </div>
  );
}
