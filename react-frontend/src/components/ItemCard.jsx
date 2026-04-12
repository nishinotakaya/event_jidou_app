import { useState, useEffect, useCallback } from 'react';
import { updateText, fetchPostingHistory, checkRegistrations, checkParticipants, syncPostingHistory, publishAllEvents, fetchGithubReviews, approveGithubReview, postGithubComment, openLocalRepo, reReviewGithub, markPostingHistorySuccess, retryErrorPosts, updatePostingHistoryUrl, fetchParticipants, syncParticipants } from '../api.js';
import { getEventStatus } from '../eventStatus.js';

// 管理URL → 公開URL変換（viewer向け）
function toPublicUrl(url, siteName) {
  if (!url) return null;
  // こくチーズ: /admin/e-XXX/d-YYY/ → /event/e-XXX/
  if (siteName === 'kokuchpro' || url.includes('kokuchpro.com/admin/')) {
    const m = url.match(/\/(e-[a-f0-9]+)\//);
    return m ? `https://www.kokuchpro.com/event/${m[1]}/` : url;
  }
  // TechPlay: owner.techplay.jp/event/XXX/edit → techplay.jp/event/XXX
  if (siteName === 'techplay' || url.includes('owner.techplay.jp')) {
    const m = url.match(/\/event\/(\d+)/);
    return m ? `https://techplay.jp/event/${m[1]}` : url;
  }
  // Doorkeeper: manage.doorkeeper.jp/groups/SLUG/events/123 → SLUG.doorkeeper.jp/events/123
  if (siteName === 'doorkeeper' || url.includes('manage.doorkeeper.jp')) {
    const m = url.match(/\/groups\/([^/]+)\/events\/(\d+)/);
    return m ? `https://${m[1]}.doorkeeper.jp/events/${m[2]}` : url;
  }
  // connpass: /published/ を除去
  if (siteName === 'connpass') {
    return url.replace(/\/published\/?$/, '/');
  }
  // Peatix: /published/ を除去
  if (siteName === 'peatix') {
    return url.replace(/\/published\/?$/, '/');
  }
  // ストアカ: そのまま公開URL
  // Luma: manage URL → 公開URL
  if (siteName === 'luma' && url.includes('/manage/')) {
    return url.replace('/event/manage/', '/');
  }
  // つなゲート: /event/edit/XXX → /events/XXX
  if (siteName === 'tunagate' && url.includes('/event/edit/')) {
    const m = url.match(/\/event\/edit\/(\d+)/);
    return m ? `https://tunagate.com/events/${m[1]}` : url;
  }
  return url;
}

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
  twitter: '𝕏', instagram: '📸', gmail: '📧', facebook: '📘', threads: '🧵',
};

const ALL_EVENT_SITES = [
  { key: 'kokuchpro', label: 'こくチーズ' }, { key: 'connpass', label: 'connpass' },
  { key: 'peatix', label: 'Peatix' }, { key: 'techplay', label: 'TechPlay' },
  { key: 'tunagate', label: 'つなゲート' }, { key: 'doorkeeper', label: 'Doorkeeper' },
  { key: 'street_academy', label: 'ストアカ' }, { key: 'eventregist', label: 'EventRegist' },
  { key: 'luma', label: 'Luma' }, { key: 'seminar_biz', label: 'セミナーBiZ' },
  { key: 'jimoty', label: 'ジモティー' },
];

const FALLBACK_URLS = {
  kokuchpro: 'https://www.kokuchpro.com/mypage/event/',
  connpass: 'https://connpass.com/editmanage/',
  peatix: 'https://peatix.com/dashboard',
  techplay: 'https://owner.techplay.jp/dashboard',
  tunagate: 'https://tunagate.com/mypage',
  doorkeeper: 'https://manage.doorkeeper.jp/groups',
  street_academy: 'https://www.street-academy.com/dashboard/steachers/myclass',
  eventregist: 'https://eventregist.com/eventlist',
  luma: 'https://lu.ma/home',
  seminar_biz: 'https://seminar-biz.com/company/seminars',
  jimoty: 'https://jmty.jp/my/posts',
};

export default function ItemCard({ item, type, folders, onEdit, onDelete, onPost, onDuplicate, onCancel, onRefresh, showToast, tagsOpen = true, userRole = 'admin' }) {
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
  const [participantsModal, setParticipantsModal] = useState(null); // { siteName, participants }
  const [participantsData, setParticipantsData] = useState({}); // { siteName: [{ name, email }] }
  const [syncingParticipantsDB, setSyncingParticipantsDB] = useState(false);
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

  const eventStatus = type === 'event' ? getEventStatus(item) : null;

  return (
    <div className={`item-card${eventStatus === 'ended' ? ' ended' : ''}`}>
      <div className="item-card-header">
        <div className="item-card-name">
          {eventStatus && (
            <span className={`event-status-badge ${eventStatus}`} style={{ marginRight: 8 }}>
              {eventStatus === 'ended' ? '🔴 終了' : '🟢 募集中'}
            </span>
          )}
          {item.name}
        </div>
        <div className="item-card-actions">
          <button
            className="btn btn-teal btn-sm"
            onClick={() => onEdit(item)}
            title={userRole === 'viewer' ? '詳細' : type === 'student' ? '編集' : '編集・投稿'}
          >
            {userRole === 'viewer' ? '詳細' : type === 'student' ? '編集' : '編集・投稿'}
          </button>
          {userRole !== 'viewer' && <button
            className="btn btn-outline btn-sm"
            onClick={() => onDuplicate(item)}
            title="複製"
          >
            複製
          </button>}
          {userRole !== 'viewer' && postingHistory.length > 0 && postingHistory.some(h => !h.published && h.status === 'success') && (
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
          {userRole !== 'viewer' && postingHistory.length > 0 && (
            <button
              className="btn btn-sm"
              style={{ background: '#f59e0b', color: '#fff', border: 'none' }}
              onClick={() => onCancel && onCancel(item)}
              title="全サイトのイベントを一斉中止"
            >
              中止
            </button>
          )}
          {userRole !== 'viewer' && <button
            className="btn btn-danger btn-sm"
            onClick={() => onDelete(item)}
            title="削除"
          >
            削除
          </button>}
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

          {postingHistory
            .filter((h) => userRole !== 'viewer' || (h.published && h.eventUrl))
            .map((h) => {
            const linkUrl = h.published
              ? (toPublicUrl(h.eventUrl, h.siteName) || h.eventUrl || FALLBACK_URLS[h.siteName] || '#')
              : (h.eventUrl || FALLBACK_URLS[h.siteName] || '#');
            const hasLink = linkUrl !== '#';
            return (
            <a
              key={h.siteName}
              href={linkUrl}
              target={hasLink ? '_blank' : undefined}
              rel="noopener noreferrer"
              onClick={async (e) => {
                // 管理者: URL未取得 or エラーのバッジクリックでURL手動入力
                if (userRole !== 'viewer' && h.id && (!h.eventUrl || h.status === 'error' || h.status === 'not_found')) {
                  e.preventDefault();
                  const url = window.prompt(`${h.siteLabel} のイベントURLを入力してください\n\n▼ イベント一覧ページ（ここからURLをコピー）\n${FALLBACK_URLS[h.siteName] || '(なし)'}`, h.eventUrl || '');
                  if (url === null) return; // キャンセル
                  try {
                    if (url.trim()) {
                      await updatePostingHistoryUrl(h.id, url.trim());
                      showToast(`${h.siteLabel} のURLを保存しました`, 'success');
                    } else {
                      await markPostingHistorySuccess(h.id);
                      showToast(`${h.siteLabel} を成功扱いにしました`, 'success');
                    }
                    const latest = await fetchPostingHistory(item.id);
                    setPostingHistory(latest);
                  } catch (err) { showToast(err.message, 'error'); }
                  return;
                }
                if (!hasLink) e.preventDefault();
              }}
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
                cursor: hasLink ? 'pointer' : 'default',
                background: h.status === 'not_found' || h.status === 'ended' ? '#fee2e2' : h.status === 'cancelled' ? '#fef3c7' : h.status === 'deleted' ? '#f3f4f6' : h.status === 'error' ? (h.errorMessage?.includes('プラン') ? '#fff7ed' : '#fee2e2') : h.published ? '#dcfce7' : '#f3f4f6',
                color: h.status === 'not_found' || h.status === 'ended' ? '#dc2626' : h.status === 'cancelled' ? '#d97706' : h.status === 'deleted' ? '#9ca3af' : h.status === 'error' ? (h.errorMessage?.includes('プラン') ? '#c2410c' : '#dc2626') : h.published ? '#16a34a' : '#6b7280',
                border: `1px solid ${h.status === 'not_found' || h.status === 'ended' ? '#fca5a5' : h.status === 'cancelled' ? '#fcd34d' : h.status === 'deleted' ? '#d1d5db' : h.status === 'error' ? (h.errorMessage?.includes('プラン') ? '#fdba74' : '#fca5a5') : h.published ? '#86efac' : '#d1d5db'}`,
                textDecorationLine: h.status === 'deleted' || h.status === 'not_found' ? 'line-through' : 'none',
                opacity: h.status === 'deleted' ? 0.6 : 1,
              }}
            >
              <span>{SITE_ICONS[h.siteName] || '📌'}</span>
              <span>{h.siteLabel}</span>
              {h.registrations != null && h.status !== 'cancelled' && h.status !== 'deleted' && <span style={{ color: '#7c3aed', fontWeight: 700 }}>({h.registrations}人)</span>}
              {h.status === 'not_found' ? <span>❌</span> : h.status === 'ended' ? <span>❌ 終了</span> : h.status === 'cancelled' ? <span>🚫 中止</span> : h.status === 'deleted' ? <span>🗑️</span> : h.status === 'error' ? (h.errorMessage?.includes('プラン') ? <span>💰 プラン</span> : <span>❌</span>) : h.published ? <span>✅</span> : <span>📝</span>}
            </a>
          );})}

          {/* 未投稿サイトを ❌ で表示 */}
          {userRole !== 'viewer' && ALL_EVENT_SITES
            .filter(s => !postingHistory.some(h => h.siteName === s.key))
            .map(s => {
              const siteUrl = FALLBACK_URLS[s.key] || '#';
              return (
                <span
                  key={s.key}
                  style={{
                    display: 'inline-flex', alignItems: 'center', gap: '3px',
                    padding: '2px 8px', borderRadius: '999px', fontSize: '11px', fontWeight: 600,
                    background: '#f3f4f6', color: '#9ca3af', border: '1px solid #e5e7eb',
                  }}
                  title={`${s.label}: 未投稿`}
                >
                  <a href={siteUrl} target="_blank" rel="noopener noreferrer" style={{ textDecoration: 'none', color: 'inherit', display: 'inline-flex', alignItems: 'center', gap: 3 }}>
                    <span>{SITE_ICONS[s.key] || '📌'}</span>
                    <span>{s.label}</span>
                  </a>
                  <span
                    onClick={async () => {
                      const url = window.prompt(`${s.label} のイベントURLを入力\n\n▼ イベント一覧ページ（ここからURLをコピー）\n${siteUrl}`, '');
                      if (!url?.trim()) return;
                      try {
                        const res = await fetch('/api/posting_histories/create_manual', {
                          method: 'POST',
                          headers: { 'Content-Type': 'application/json' },
                          body: JSON.stringify({ item_id: item.id, site_name: s.key, event_url: url.trim() }),
                        });
                        if (!res.ok) throw new Error('保存失敗');
                        showToast(`${s.label} のURLを保存しました`, 'success');
                        const latest = await fetchPostingHistory(item.id);
                        setPostingHistory(latest);
                      } catch (err) { showToast(err.message, 'error'); }
                    }}
                    style={{ cursor: 'pointer', marginLeft: 2 }}
                    title="クリックでURL手動入力"
                  >✏️</span>
                </span>
              );
            })
          }

          {userRole !== 'viewer' && <button
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
          </button>}
          {userRole !== 'viewer' && postingHistory.some(h => h.status === 'error' || h.status === 'not_found' || (h.status === 'success' && !h.published)) && (
            <button
              onClick={async () => {
                const errSites = postingHistory.filter(h => h.status === 'error' || h.status === 'not_found' || (h.status === 'success' && !h.published)).map(h => `${h.siteLabel}(${h.status === 'error' ? '❌' : h.status === 'not_found' ? '❌' : '📝'})`).join(', ');
                if (!window.confirm(`❌ のサイト（${errSites}）に再投稿しますか？`)) return;
                showToast('🔄 再投稿開始...', 'info');
                try {
                  await retryErrorPosts(item.id, (event) => {
                    if (event.type === 'log') showToast(event.message, 'info');
                    else if (event.type === 'error') showToast(event.message, 'error');
                    else if (event.type === 'status') {
                      // リアルタイムでタグ色更新
                      setPostingHistory((prev) => prev.map((ph) =>
                        ph.siteLabel === event.site || ph.siteName === event.site
                          ? { ...ph, status: event.status, published: event.status === 'success' }
                          : ph
                      ));
                    } else if (event.type === 'done') {
                      showToast('再投稿完了', 'success');
                      // 最終データを取得して確定
                      fetchPostingHistory(item.id).then(setPostingHistory).catch(() => {});
                    }
                  });
                } catch (err) { showToast(err.message, 'error'); }
              }}
              style={{
                display: 'inline-flex', alignItems: 'center', gap: '3px',
                padding: '2px 8px', borderRadius: '999px', fontSize: '11px', fontWeight: 600,
                background: '#dbeafe', color: '#2563eb', border: '1px solid #93c5fd',
                cursor: 'pointer',
              }}
              title="❌ のサイトだけ再投稿する"
            >
              🔄 再投稿
            </button>
          )}
          {userRole !== 'viewer' && <button
            onClick={async () => {
              try {
                const data = await fetchParticipants(item.id);
                setParticipantsData(data.participants || {});
                const total = Object.values(data.participants || {}).flat().length;
                if (total > 0) {
                  setParticipantsModal({ all: true });
                } else {
                  showToast('参加者データなし。「🔄 参加者同期」で取得してください', 'info');
                }
              } catch (err) { showToast(err.message, 'error'); }
            }}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: '3px',
              padding: '2px 8px', borderRadius: '999px', fontSize: '11px', fontWeight: 600,
              background: '#fef3c7', color: '#d97706', border: '1px solid #fcd34d',
              cursor: 'pointer',
            }}
            title="DBから参加者一覧を表示"
          >
            👥 参加者確認
          </button>}
          {userRole !== 'viewer' && <button
            onClick={async () => {
              setSyncingParticipantsDB(true);
              showToast('🔄 参加者同期中...', 'info');
              try {
                const data = await syncParticipants(item.id);
                setParticipantsData(data.participants || {});
                showToast(`参加者同期完了（${data.total}名）`, 'success');
                // 申し込み数も更新
                const latest = await fetchPostingHistory(item.id);
                setPostingHistory(latest);
              } catch (err) { showToast(err.message, 'error'); }
              finally { setSyncingParticipantsDB(false); }
            }}
            disabled={syncingParticipantsDB}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: '3px',
              padding: '2px 8px', borderRadius: '999px', fontSize: '11px', fontWeight: 600,
              background: '#d1fae5', color: '#059669', border: '1px solid #6ee7b7',
              cursor: syncingParticipantsDB ? 'wait' : 'pointer',
            }}
            title="各サイトから参加者を取得してDBに保存"
          >
            {syncingParticipantsDB ? '⏳ 同期中...' : '🔄 参加者同期'}
          </button>}
        {userRole !== 'viewer' && <button
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
        </button>}
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

      {/* 参加者モーダル */}
      {participantsModal && (
        <div
          onClick={() => setParticipantsModal(null)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
        >
          <div onClick={(e) => e.stopPropagation()} style={{ background: '#fff', borderRadius: 12, padding: 20, width: '90%', maxWidth: 600, maxHeight: '70vh', overflow: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <h3 style={{ margin: 0, fontSize: 16 }}>👥 参加者一覧</h3>
              <button onClick={() => setParticipantsModal(null)} style={{ background: 'none', border: 'none', fontSize: 18, cursor: 'pointer' }}>✕</button>
            </div>
            {Object.keys(participantsData).length === 0 ? (
              <p style={{ color: '#9ca3af', textAlign: 'center', padding: 20 }}>参加者データなし。「🔄 参加者同期」で取得してください。</p>
            ) : (
              Object.entries(participantsData).map(([site, list]) => (
                <div key={site} style={{ marginBottom: 16 }}>
                  <h4 style={{ margin: '0 0 8px', fontSize: 14, color: '#374151' }}>
                    {SITE_ICONS[site] || '📌'} {PostingHistory?.SITE_LABELS?.[site] || site}（{list.length}名）
                  </h4>
                  {list.length === 0 ? (
                    <p style={{ fontSize: 12, color: '#9ca3af', marginLeft: 16 }}>参加者なし</p>
                  ) : (
                    <table style={{ width: '100%', fontSize: 12, borderCollapse: 'collapse' }}>
                      <thead>
                        <tr style={{ borderBottom: '1px solid #e5e7eb' }}>
                          <th style={{ textAlign: 'left', padding: '4px 8px', color: '#6b7280' }}>名前</th>
                          <th style={{ textAlign: 'left', padding: '4px 8px', color: '#6b7280' }}>メール</th>
                        </tr>
                      </thead>
                      <tbody>
                        {list.map((p, i) => (
                          <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                            <td style={{ padding: '4px 8px' }}>{p.name || '—'}</td>
                            <td style={{ padding: '4px 8px', color: '#6b7280' }}>{p.email || '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
