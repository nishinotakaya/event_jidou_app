import { useState, useEffect } from 'react';
import { fetchPostingHistory } from '../api.js';

// content から Zoom URL / ミーティングID / パスコードを抽出
function extractZoomInfo(content) {
  if (!content) return null;
  const urlMatch = content.match(/https?:\/\/[\w.-]*zoom\.us\/[^\s\u3000）)」]+/i);
  const idMatch = content.match(/(?:ミーティング\s*ID|Meeting\s*ID)[:：]\s*([0-9 \-]{9,})/i);
  const pwMatch = content.match(/(?:パスコード|Passcode|パスワード)[:：]\s*([^\s\u3000]+)/i);
  if (!urlMatch && !idMatch && !pwMatch) return null;
  return {
    url: urlMatch ? urlMatch[0] : '',
    meetingId: idMatch ? idMatch[1].trim() : '',
    passcode: pwMatch ? pwMatch[1].trim() : '',
  };
}

const SITE_ICONS = {
  kokuchpro: '🟠', peatix: '🟡', connpass: '🔴', techplay: '🔵',
  tunagate: '🤝', doorkeeper: '🚪', street_academy: '🎓', eventregist: '📋',
  luma: '✨', seminar_biz: '💼', jimoty: '📍', passmarket: '🎫',
  seminars: '📚', LME: '💬', instagram: '📸', twitter: '🐦',
  facebook: '📘', threads: '🧵', onclass: '🏫', gmail: '📧',
};

const SITE_LABELS = {
  kokuchpro: 'こくチーズ', peatix: 'Peatix', connpass: 'connpass', techplay: 'TechPlay',
  tunagate: 'つなゲート', doorkeeper: 'Doorkeeper', street_academy: 'ストアカ', eventregist: 'EventRegist',
  luma: 'Luma', seminar_biz: 'セミナーBiZ', jimoty: 'ジモティー', passmarket: 'PassMarket',
  seminars: 'セミナーズ', LME: 'LME', instagram: 'Instagram', twitter: 'X',
  facebook: 'Facebook', threads: 'Threads', onclass: 'オンクラス', gmail: 'Gmail',
};

function toPublicUrl(url, siteName) {
  if (!url) return null;
  if (siteName === 'kokuchpro' && url.includes('/admin/')) {
    const m = url.match(/\/(e-[a-f0-9]+)\//);
    return m ? `https://www.kokuchpro.com/event/${m[1]}/` : url;
  }
  if (siteName === 'techplay' && url.includes('owner.techplay.jp')) {
    const m = url.match(/\/event\/(\d+)/);
    return m ? `https://techplay.jp/event/${m[1]}` : url;
  }
  if (siteName === 'doorkeeper' && url.includes('manage.doorkeeper.jp')) {
    const m = url.match(/\/groups\/([^/]+)\/events\/(\d+)/);
    return m ? `https://${m[1]}.doorkeeper.jp/events/${m[2]}` : url;
  }
  if (siteName === 'connpass') return url.replace(/\/published\/?$/, '/');
  if (siteName === 'peatix') return url.replace(/\/published\/?$/, '/');
  if (siteName === 'luma') {
    if (url.includes('/manage/')) return url.replace('/event/manage/', '/').replace('luma.com/', 'lu.ma/');
    if (url === 'about:blank' || url.includes('/create') || !url.includes('lu.ma/')) return null;
  }
  if (siteName === 'tunagate' && url.includes('/event/edit/')) {
    const m = url.match(/\/event\/edit\/(\d+)/);
    return m ? `https://tunagate.com/events/${m[1]}` : url;
  }
  return url;
}

export default function DetailModal({ item, onClose }) {
  const [histories, setHistories] = useState([]);
  const [loadingHistories, setLoadingHistories] = useState(false);

  useEffect(() => {
    if (!item?.id) return;
    setLoadingHistories(true);
    fetchPostingHistory(item.id)
      .then((data) => setHistories(data || []))
      .catch(() => setHistories([]))
      .finally(() => setLoadingHistories(false));
  }, [item?.id]);

  if (!item) return null;

  const extracted = extractZoomInfo(item.content);
  const zoom = {
    url: item.zoomUrl || extracted?.url || '',
    meetingId: extracted?.meetingId || '',
    passcode: extracted?.passcode || '',
  };

  const successHistories = histories.filter(h => h.status === 'success' || h.status === 'draft');

  return (
    <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="modal" style={{ maxWidth: '640px', maxHeight: '85vh', display: 'flex', flexDirection: 'column' }}>
        <div className="modal-header">
          <h2 className="modal-title">{item.name || 'イベント詳細'}</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>
        <div className="modal-body" style={{ overflowY: 'auto', flex: 1 }}>
          {/* 基本情報 */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', marginBottom: '16px' }}>
            {item.eventDate && (
              <div>
                <span style={{ fontSize: '11px', color: '#6b7280' }}>開催日</span>
                <div style={{ fontSize: '14px', fontWeight: 600 }}>{item.eventDate}</div>
              </div>
            )}
            {item.eventTime && (
              <div>
                <span style={{ fontSize: '11px', color: '#6b7280' }}>時間</span>
                <div style={{ fontSize: '14px', fontWeight: 600 }}>
                  {item.eventTime}{item.eventEndTime ? ` 〜 ${item.eventEndTime}` : ''}
                </div>
              </div>
            )}
            {item.folder && (
              <div>
                <span style={{ fontSize: '11px', color: '#6b7280' }}>フォルダ</span>
                <div style={{ fontSize: '13px' }}>{item.folder}</div>
              </div>
            )}
            {item.type && (
              <div>
                <span style={{ fontSize: '11px', color: '#6b7280' }}>タイプ</span>
                <div style={{ fontSize: '13px' }}>{item.type === 'event' ? 'イベント告知' : '受講生サポート'}</div>
              </div>
            )}
          </div>

          {/* 投稿状況 */}
          {item.type === 'event' && (
            <div style={{
              marginBottom: '16px',
              padding: '12px',
              background: '#f0fdf4',
              border: '1px solid #bbf7d0',
              borderRadius: '8px',
            }}>
              <div style={{ fontSize: '12px', fontWeight: 700, color: '#16a34a', marginBottom: '8px' }}>
                📢 投稿状況 {histories.length > 0 && `(${successHistories.length}サイト)`}
              </div>
              {loadingHistories ? (
                <div style={{ fontSize: '12px', color: '#9ca3af' }}>読み込み中...</div>
              ) : histories.length === 0 ? (
                <div style={{ fontSize: '12px', color: '#9ca3af' }}>投稿履歴なし</div>
              ) : (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                  {histories.map((h, i) => {
                    const publicUrl = toPublicUrl(h.eventUrl, h.siteName);
                    const icon = SITE_ICONS[h.siteName] || '📌';
                    const label = SITE_LABELS[h.siteName] || h.siteName;
                    const statusColor = h.status === 'success' ? '#16a34a'
                      : h.status === 'draft' ? '#d97706'
                      : h.status === 'error' ? '#dc2626' : '#9ca3af';
                    const statusIcon = h.status === 'success' ? '✅'
                      : h.status === 'draft' ? '📝'
                      : h.status === 'error' ? '❌' : '⚠️';
                    const reg = h.registrations != null ? ` (${h.registrations}人)` : '';

                    return publicUrl && h.status !== 'error' ? (
                      <a
                        key={i}
                        href={publicUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{
                          display: 'inline-flex', alignItems: 'center', gap: '3px',
                          padding: '3px 8px', borderRadius: '12px', fontSize: '11px',
                          background: h.status === 'success' ? '#dcfce7' : '#fef3c7',
                          color: statusColor, border: `1px solid ${statusColor}33`,
                          textDecoration: 'none', fontWeight: 500,
                        }}
                        title={`${label}で開く${reg}`}
                      >
                        {icon} {label}{reg}
                      </a>
                    ) : (
                      <span
                        key={i}
                        style={{
                          display: 'inline-flex', alignItems: 'center', gap: '3px',
                          padding: '3px 8px', borderRadius: '12px', fontSize: '11px',
                          background: '#fee2e2', color: statusColor,
                          border: `1px solid ${statusColor}33`, fontWeight: 500,
                        }}
                        title={h.errorMessage || label}
                      >
                        {icon} {label} {statusIcon}
                      </span>
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {/* Zoom 参加情報 */}
          {item.type === 'event' && (
            <div style={{
              marginBottom: '16px',
              padding: '12px',
              background: '#eff6ff',
              border: '1px solid #bfdbfe',
              borderRadius: '8px',
            }}>
              <div style={{ fontSize: '12px', fontWeight: 700, color: '#1d4ed8', marginBottom: '6px' }}>
                🎥 Zoom 参加情報
              </div>
              <div style={{ marginBottom: '4px' }}>
                <span style={{ fontSize: '11px', color: '#6b7280', marginRight: '6px' }}>参加URL</span>
                {zoom.url ? (
                  <a
                    href={zoom.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{ fontSize: '13px', color: '#2563eb', wordBreak: 'break-all', textDecoration: 'underline' }}
                  >
                    {zoom.url}
                  </a>
                ) : (
                  <span style={{ fontSize: '13px', color: '#9ca3af' }}>未設定</span>
                )}
              </div>
              {zoom.meetingId && (
                <div style={{ fontSize: '13px', marginBottom: '2px' }}>
                  <span style={{ fontSize: '11px', color: '#6b7280', marginRight: '6px' }}>ミーティングID</span>
                  {zoom.meetingId}
                </div>
              )}
              {zoom.passcode && (
                <div style={{ fontSize: '13px' }}>
                  <span style={{ fontSize: '11px', color: '#6b7280', marginRight: '6px' }}>パスコード</span>
                  {zoom.passcode}
                </div>
              )}
            </div>
          )}

          {/* 内容 */}
          <div style={{ marginBottom: '16px' }}>
            <span style={{ fontSize: '11px', color: '#6b7280', display: 'block', marginBottom: '4px' }}>内容</span>
            <div style={{
              padding: '12px',
              background: '#f9fafb',
              borderRadius: '8px',
              border: '1px solid #e5e7eb',
              fontSize: '13px',
              lineHeight: 1.7,
              whiteSpace: 'pre-wrap',
              maxHeight: '400px',
              overflowY: 'auto',
            }}>
              {item.content || '（内容なし）'}
            </div>
          </div>

          {/* メタ情報 */}
          <div style={{ fontSize: '11px', color: '#9ca3af' }}>
            {item.createdAt && <span>作成: {item.createdAt}</span>}
            {item.updatedAt && <span style={{ marginLeft: '12px' }}>更新: {item.updatedAt}</span>}
          </div>
        </div>
      </div>
    </div>
  );
}
