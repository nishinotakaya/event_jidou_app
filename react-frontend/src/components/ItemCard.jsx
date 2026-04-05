import { useState, useEffect, useCallback } from 'react';
import { updateText, fetchPostingHistory, checkRegistrations, checkParticipants, syncPostingHistory, publishAllEvents, fetchGithubReviews, approveGithubReview, postGithubComment, openLocalRepo, reReviewGithub } from '../api.js';

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

const SITE_ICONS = {
  kokuchpro: '🟠', connpass: '🔴', peatix: '🟡', techplay: '🔵',
  tunagate: '🤝', doorkeeper: '🚪', seminars: '📢', street_academy: '🎓',
  eventregist: '📋', passmarket: '🅿️', luma: '✨', seminar_biz: '💼', jimoty: '📍',
  twitter: '𝕏', instagram: '📸', gmail: '📧',
};

export default function ItemCard({ item, type, folders, onEdit, onDelete, onPost, onDuplicate, onCancel, onRefresh, showToast, tagsOpen = true }) {
  const [expanded, setExpanded] = useState(tagsOpen);
  useEffect(() => { setExpanded(tagsOpen); }, [tagsOpen]);
  const [movingFolder, setMovingFolder] = useState(false);
  const [postingHistory, setPostingHistory] = useState([]);
  const [checkingRegs, setCheckingRegs] = useState(false);
  const [checkingParticipants, setCheckingParticipants] = useState(false);
  const [participantData, setParticipantData] = useState(null);
  const [showParticipants, setShowParticipants] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [githubReview, setGithubReview] = useState(null);
  const [postingToGithub, setPostingToGithub] = useState(false);
  const folderOptions = buildFolderOptions(folders);

  const isGitReview = item?.folder === 'Gitレビュー';

  useEffect(() => {
    if (item?.id && type === 'event') {
      fetchPostingHistory(item.id).then(setPostingHistory).catch(() => {});
    }
    // Gitレビューの場合、関連するGithubReviewレコードを取得
    if (isGitReview && item?.id) {
      fetchGithubReviews().then((reviews) => {
        const match = reviews.find(r => r.item_id === item.id);
        if (match) setGithubReview(match);
      }).catch(() => {});
    }
  }, [item?.id, type]);

  const handleCheckRegistrations = useCallback(async () => {
    if (!item?.id) return;
    setCheckingRegs(true);
    try {
      const updated = await checkRegistrations(item.id);
      setPostingHistory(updated);
      showToast('申し込み数を更新しました', 'success');
    } catch (err) {
      showToast('申し込み数の取得に失敗しました', 'error');
    } finally {
      setCheckingRegs(false);
    }
  }, [item?.id, showToast]);

  const handleSync = useCallback(async () => {
    if (!item?.id) return;
    setSyncing(true);
    try {
      const updated = await syncPostingHistory(item.id);
      setPostingHistory(updated);
      showToast('ポータルサイトと同期しました', 'success');
    } catch (err) {
      showToast('同期に失敗しました', 'error');
    } finally {
      setSyncing(false);
    }
  }, [item?.id, showToast]);

  const handlePublishAll = useCallback(async () => {
    if (!item?.id) return;
    const unpublished = postingHistory.filter(h => !h.published && h.status === 'success');
    if (unpublished.length === 0) { showToast('公開対象のサイトがありません', 'info'); return; }
    setPublishing(true);
    try {
      await publishAllEvents(item.id, (event) => {
        if (event.type === 'done') {
          fetchPostingHistory(item.id).then(setPostingHistory).catch(() => {});
          showToast('全サイト公開処理が完了しました', 'success');
        }
      });
    } catch (err) {
      showToast('公開処理に失敗しました', 'error');
    } finally {
      setPublishing(false);
    }
  }, [item?.id, postingHistory, showToast]);

  const handleCheckParticipants = useCallback(async () => {
    if (!item?.id) return;
    setCheckingParticipants(true);
    try {
      const data = await checkParticipants(item.id);
      setParticipantData(data);
      setShowParticipants(true);
      showToast('参加者情報を取得しました', 'success');
    } catch (err) {
      showToast('参加者情報の取得に失敗しました', 'error');
    } finally {
      setCheckingParticipants(false);
    }
  }, [item?.id, showToast]);

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
            onClick={() => onEdit(item)}
            title="編集・投稿"
          >
            編集・投稿
          </button>
          <button
            className="btn btn-outline btn-sm"
            onClick={() => onDuplicate(item)}
            title="複製"
          >
            複製
          </button>
          {postingHistory.length > 0 && postingHistory.some(h => !h.published && h.status === 'success') && (
            <button
              className="btn btn-sm"
              style={{ background: '#16a34a', color: '#fff', border: 'none' }}
              onClick={handlePublishAll}
              disabled={publishing}
              title="下書きを全サイト一括公開"
            >
              {publishing ? '⏳' : '📢'} 全公開
            </button>
          )}
          {postingHistory.length > 0 && (
            <button
              className="btn btn-sm"
              style={{ background: '#f59e0b', color: '#fff', border: 'none' }}
              onClick={() => onCancel && onCancel(item)}
              title="全サイトのイベントを一斉中止"
            >
              中止
            </button>
          )}
          <button
            className="btn btn-danger btn-sm"
            onClick={() => onDelete(item)}
            title="削除"
          >
            削除
          </button>
        </div>
      </div>

      {/* フォルダバッジは非表示（フォルダ移動セレクトで確認可能） */}

      {item.eventDate && (
        <div className="item-card-event-date">
          📅 {item.eventDate}{(() => { const d = new Date(item.eventDate); return isNaN(d) ? '' : `（${'日月火水木金土'[d.getDay()]}）`; })()}{item.eventTime ? ` ${item.eventTime}` : ''}{item.eventEndTime ? `〜${item.eventEndTime}` : ''}
        </div>
      )}

      <div className="item-card-content">{item.content}</div>

      {/* 投稿履歴バッジ + 同期（アコーディオン） */}
      <div style={{ margin: '8px 0' }}>
        <button
          onClick={() => setExpanded(!expanded)}
          style={{
            display: 'inline-flex', alignItems: 'center', gap: '4px',
            background: 'none', border: 'none', cursor: 'pointer',
            fontSize: '11px', fontWeight: 600, color: '#6b7280',
            padding: '2px 0', marginBottom: expanded ? '6px' : 0,
          }}
        >
          <span style={{ transition: 'transform .15s', transform: expanded ? 'rotate(90deg)' : 'rotate(0deg)', display: 'inline-block' }}>▶</span>
          投稿状況{postingHistory.length > 0 ? ` (${postingHistory.length})` : ''}
        </button>
        {expanded && <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px', alignItems: 'center' }}>
        {postingHistory.length > 0 && (<>

          {postingHistory.map((h) => (
            <a
              key={h.siteName}
              href={h.eventUrl || '#'}
              target={h.eventUrl ? '_blank' : undefined}
              rel="noopener noreferrer"
              onClick={(e) => { if (!h.eventUrl) e.preventDefault(); }}
              title={`${h.siteLabel}${h.status === 'not_found' ? '（存在しない）' : h.status === 'ended' ? '（終了）' : h.status === 'cancelled' ? '（中止）' : h.status === 'deleted' ? '（削除済み）' : h.published ? '（公開済み）' : '（下書き）'}${h.registrations != null ? `\n申し込み: ${h.registrations}人` : ''}${h.eventUrl ? '\nクリックで詳細ページへ' : ''}\n投稿日: ${h.postedAt ? new Date(h.postedAt).toLocaleString('ja-JP') : ''}`}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '3px',
                padding: '2px 8px',
                borderRadius: '999px',
                fontSize: '11px',
                fontWeight: 600,
                textDecoration: 'none',
                cursor: h.eventUrl ? 'pointer' : 'default',
                background: h.status === 'not_found' || h.status === 'ended' ? '#fee2e2' : h.status === 'cancelled' ? '#fef3c7' : h.status === 'deleted' ? '#f3f4f6' : h.status === 'error' ? '#fee2e2' : h.published ? '#dcfce7' : '#f3f4f6',
                color: h.status === 'not_found' || h.status === 'ended' ? '#dc2626' : h.status === 'cancelled' ? '#d97706' : h.status === 'deleted' ? '#9ca3af' : h.status === 'error' ? '#dc2626' : h.published ? '#16a34a' : '#6b7280',
                border: `1px solid ${h.status === 'not_found' || h.status === 'ended' ? '#fca5a5' : h.status === 'cancelled' ? '#fcd34d' : h.status === 'deleted' ? '#d1d5db' : h.status === 'error' ? '#fca5a5' : h.published ? '#86efac' : '#d1d5db'}`,
                textDecorationLine: h.status === 'deleted' || h.status === 'not_found' ? 'line-through' : 'none',
                opacity: h.status === 'deleted' ? 0.6 : 1,
              }}
            >
              <span>{SITE_ICONS[h.siteName] || '📌'}</span>
              <span>{h.siteLabel}</span>
              {h.registrations != null && h.status !== 'cancelled' && h.status !== 'deleted' && <span style={{ color: '#7c3aed', fontWeight: 700 }}>({h.registrations}人)</span>}
              {h.status === 'not_found' ? <span>❌</span> : h.status === 'ended' ? <span>❌ 終了</span> : h.status === 'cancelled' ? <span>🚫 中止</span> : h.status === 'deleted' ? <span>🗑️</span> : h.status === 'error' ? <span>❌</span> : h.published ? <span>✅</span> : <span>📝</span>}
            </a>
          ))}
          <button
            onClick={handleCheckRegistrations}
            disabled={checkingRegs}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: '3px',
              padding: '2px 8px', borderRadius: '999px', fontSize: '11px', fontWeight: 600,
              background: '#ede9fe', color: '#7c3aed', border: '1px solid #c4b5fd',
              cursor: checkingRegs ? 'wait' : 'pointer',
            }}
            title="各サイトの申し込み数を確認"
          >
            {checkingRegs ? '⏳' : '🔄'} 申し込み確認
          </button>
          <button
            onClick={handleCheckParticipants}
            disabled={checkingParticipants}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: '3px',
              padding: '2px 8px', borderRadius: '999px', fontSize: '11px', fontWeight: 600,
              background: '#fef3c7', color: '#d97706', border: '1px solid #fcd34d',
              cursor: checkingParticipants ? 'wait' : 'pointer',
            }}
            title="各サイトの参加者名・メールアドレスを取得"
          >
            {checkingParticipants ? '⏳ 取得中...' : '👥 参加者確認'}
          </button>
        </>)}
        <button
          onClick={handleSync}
          disabled={syncing}
          style={{
            display: 'inline-flex', alignItems: 'center', gap: '3px',
            padding: '2px 8px', borderRadius: '999px', fontSize: '11px', fontWeight: 600,
            background: '#e0f2fe', color: '#0284c7', border: '1px solid #7dd3fc',
            cursor: syncing ? 'wait' : 'pointer',
          }}
          title="各ポータルサイトのイベント生存確認"
        >
          {syncing ? '⏳' : '🔄'} 同期
        </button>
      </div>}
      </div>

      {/* 参加者一覧 */}
      {showParticipants && participantData && (
        <div style={{ margin: '8px 0', padding: '10px', background: '#fafafa', borderRadius: '8px', border: '1px solid #e5e7eb' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
            <span style={{ fontWeight: 700, fontSize: '13px' }}>👥 参加者一覧</span>
            <button
              onClick={() => setShowParticipants(false)}
              style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '14px', color: '#9ca3af' }}
            >✕</button>
          </div>
          {Object.entries(participantData).map(([siteName, data]) => (
            <div key={siteName} style={{ marginBottom: '10px' }}>
              <div style={{ fontSize: '12px', fontWeight: 600, color: '#374151', marginBottom: '4px' }}>
                {SITE_ICONS[siteName] || '📌'} {data.site_label || siteName}
                <span style={{ color: '#9ca3af', fontWeight: 400, marginLeft: '6px' }}>
                  {data.participants?.length || 0}人
                </span>
                {data.error && <span style={{ color: '#dc2626', marginLeft: '6px' }}>(エラー: {data.error.substring(0, 40)})</span>}
              </div>
              {data.participants?.length > 0 ? (
                <table style={{ width: '100%', fontSize: '11px', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ background: '#f3f4f6' }}>
                      <th style={{ padding: '3px 6px', textAlign: 'left', borderBottom: '1px solid #e5e7eb' }}>名前</th>
                      <th style={{ padding: '3px 6px', textAlign: 'left', borderBottom: '1px solid #e5e7eb' }}>メールアドレス</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.participants.map((p, i) => (
                      <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                        <td style={{ padding: '3px 6px' }}>{p.name || '-'}</td>
                        <td style={{ padding: '3px 6px', color: '#3b82f6' }}>{p.email || '-'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : (
                !data.error && <div style={{ fontSize: '11px', color: '#9ca3af', paddingLeft: '6px' }}>参加者なし</div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* GitHub レビュー操作（Gitレビューフォルダのアイテムのみ） */}
      {isGitReview && githubReview && (
        <div style={{ padding: '10px 12px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0', margin: '4px 0' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '6px' }}>
            <span style={{ fontSize: '12px', fontWeight: 700, color: '#1f2937' }}>
              🔍 GitHubレビュー
            </span>
            <span style={{
              fontSize: '10px', fontWeight: 600, padding: '2px 8px', borderRadius: '999px',
              background: githubReview.status === 'posted' ? '#dcfce7' : githubReview.status === 'approved' ? '#dbeafe' : githubReview.status === 'reviewed' ? '#fef3c7' : '#f3f4f6',
              color: githubReview.status === 'posted' ? '#16a34a' : githubReview.status === 'approved' ? '#2563eb' : githubReview.status === 'reviewed' ? '#d97706' : '#6b7280',
            }}>
              {githubReview.status === 'posted' ? '✅ 投稿済み' : githubReview.status === 'approved' ? '👍 承認済み' : githubReview.status === 'reviewed' ? '📝 レビュー済み' : '⏳ 待機中'}
            </span>
          </div>
          <a href={githubReview.github_url} target="_blank" rel="noopener noreferrer" style={{ fontSize: '11px', color: '#3b82f6', wordBreak: 'break-all' }}>
            {githubReview.github_url}
          </a>
          {githubReview.github_comment_url && (
            <div style={{ marginTop: '4px' }}>
              <a href={githubReview.github_comment_url} target="_blank" rel="noopener noreferrer" style={{ fontSize: '11px', color: '#16a34a' }}>
                💬 投稿済みコメントを見る
              </a>
            </div>
          )}
          <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
            {githubReview.status === 'reviewed' && (
              <button
                className="btn btn-sm"
                style={{ background: '#dbeafe', color: '#2563eb', border: '1px solid #93c5fd', fontSize: '11px' }}
                onClick={async () => {
                  try {
                    await approveGithubReview(githubReview.id);
                    setGithubReview({ ...githubReview, status: 'approved' });
                    showToast('レビューを承認しました', 'success');
                  } catch (e) { showToast(e.message, 'error'); }
                }}
              >
                👍 承認
              </button>
            )}
            {githubReview.status === 'approved' && (
              <button
                className="btn btn-sm"
                style={{ background: '#dcfce7', color: '#16a34a', border: '1px solid #86efac', fontSize: '11px' }}
                disabled={postingToGithub}
                onClick={async () => {
                  setPostingToGithub(true);
                  try {
                    const result = await postGithubComment(githubReview.id, item.content);
                    setGithubReview({ ...githubReview, status: 'posted', github_comment_url: result.comment_url });
                    showToast('GitHubにコメントを投稿しました！', 'success');
                  } catch (e) { showToast(e.message, 'error'); }
                  finally { setPostingToGithub(false); }
                }}
              >
                {postingToGithub ? '⏳ 投稿中...' : '🚀 GitHubに投稿'}
              </button>
            )}
            <button
              className="btn btn-sm"
              style={{ background: '#eef2ff', color: '#4f46e5', border: '1px solid #c7d2fe', fontSize: '11px' }}
              onClick={async () => {
                try {
                  const result = await openLocalRepo(githubReview.id);
                  showToast(`VS Codeで開きました（${result.action === 'clone' ? '新規クローン' : 'git pull'}）`, 'success');
                } catch (e) { showToast(e.message, 'error'); }
              }}
            >
              💻 VS Codeで開く
            </button>
            <button
              className="btn btn-sm"
              style={{ background: '#fef3c7', color: '#d97706', border: '1px solid #fcd34d', fontSize: '11px' }}
              onClick={async () => {
                showToast('🔄 再レビュー開始...', 'info');
                try {
                  await reReviewGithub(githubReview.id, (event) => {
                    if (event.type === 'log') showToast(event.message, 'info');
                    else if (event.type === 'done') {
                      showToast(event.message, 'success');
                      fetchGithubReviews().then((reviews) => {
                        const match = reviews.find(r => r.item_id === item.id);
                        if (match) setGithubReview(match);
                      }).catch(() => {});
                      if (onRefresh) onRefresh();
                    }
                    else if (event.type === 'error') showToast(event.message, 'error');
                  });
                } catch (e) { showToast(e.message, 'error'); }
              }}
            >
              🔄 再レビュー
            </button>
          </div>
        </div>
      )}

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
