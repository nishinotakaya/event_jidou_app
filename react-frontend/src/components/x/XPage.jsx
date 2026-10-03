import { useState, useEffect, useCallback } from 'react';
import { xListPosts, xFetchStatus } from './xApi.js';
import XCalendar from './XCalendar.jsx';
import XPostList from './XPostList.jsx';
import XPostModal from './XPostModal.jsx';
import XConnectModal from './XConnectModal.jsx';
import XGenerateModal from './XGenerateModal.jsx';

const TABS = [
  { key: 'calendar', label: 'カレンダー' },
  { key: 'list',     label: '一覧' },
  { key: 'generate', label: 'AI生成' },
  { key: 'connect',  label: '接続設定' },
];

export default function XPage({ showToast }) {
  const [tab, setTab] = useState('calendar');
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState({ connected: false, screenName: null, lastTestedAt: null });

  const [postModal, setPostModal] = useState(null);     // null | { post?, defaultDate? }
  const [connectOpen, setConnectOpen] = useState(false);
  const [generateOpen, setGenerateOpen] = useState(false);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const [list, s] = await Promise.all([xListPosts(), xFetchStatus()]);
      setPosts(list || []);
      setStatus(s || { connected: false });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    reload();
  }, [reload]);

  useEffect(() => {
    if (tab === 'generate') setGenerateOpen(true);
    if (tab === 'connect')  setConnectOpen(true);
  }, [tab]);

  return (
    <div style={{ padding: '0 24px 24px' }}>
      <div style={{
        background: '#faf8ff',
        border: '1.5px solid #e2d9f3',
        borderRadius: '12px',
        padding: '14px 18px',
        marginBottom: '16px',
        display: 'flex',
        alignItems: 'center',
        gap: '16px',
        flexWrap: 'wrap',
      }}>
        <div>
          <h2 style={{ margin: 0, fontSize: '16px', color: '#3b1f6e' }}>𝕏 自動投稿</h2>
          <p style={{ margin: '2px 0 0', fontSize: '12px', color: '#6b4fa0' }}>
            予約ツイートの管理と、1ヶ月分の下書きを AI でまとめて作るためのページ。
          </p>
        </div>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: '12px' }}>
          <span style={{
            fontSize: '12px',
            padding: '4px 10px',
            borderRadius: '999px',
            background: status.connected ? '#dcfce7' : '#f3f4f6',
            color: status.connected ? '#166534' : '#6b7280',
            border: `1px solid ${status.connected ? '#86efac' : '#d1d5db'}`,
            fontWeight: 600,
          }}>
            {status.connected ? `接続済み${status.screenName ? `（@${status.screenName}）` : ''}` : '未接続'}
          </span>
          <button
            className="btn btn-primary"
            onClick={() => setPostModal({})}
          >
            + 新規作成
          </button>
        </div>
      </div>

      <div className="type-tabs" style={{ marginBottom: '16px' }}>
        {TABS.map((t) => (
          <button
            key={t.key}
            className={`type-tab ${tab === t.key ? 'active' : ''}`}
            onClick={() => setTab(t.key)}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'calendar' && (
        <XCalendar
          posts={posts}
          onEditPost={(p) => setPostModal({ post: p })}
          onCreateOnDate={(dateStr) => {
            const d = new Date(`${dateStr}T09:00:00`);
            setPostModal({ defaultDate: d.toISOString() });
          }}
          onChanged={reload}
          onNeedConnect={() => setConnectOpen(true)}
          showToast={showToast}
        />
      )}

      {tab === 'list' && (
        <XPostList
          posts={posts}
          loading={loading}
          onEdit={(p) => setPostModal({ post: p })}
          onChanged={reload}
          onNeedConnect={() => setConnectOpen(true)}
          showToast={showToast}
        />
      )}

      {/* generate / connect タブはモーダルを出す。閉じたらカレンダーに戻す。 */}
      {tab === 'generate' && !generateOpen && (
        <div style={{ padding: '40px', textAlign: 'center', color: '#9878cc' }}>
          モーダルが閉じられました。タブを切り替えるか、再度「AI生成」を押してください。
        </div>
      )}
      {tab === 'connect' && !connectOpen && (
        <div style={{ padding: '40px', textAlign: 'center', color: '#9878cc' }}>
          モーダルが閉じられました。タブを切り替えるか、再度「接続設定」を押してください。
        </div>
      )}

      {postModal && (
        <XPostModal
          post={postModal.post || null}
          defaultDate={postModal.defaultDate || null}
          onClose={() => setPostModal(null)}
          onSaved={reload}
          showToast={showToast}
        />
      )}

      {generateOpen && (
        <XGenerateModal
          onClose={() => { setGenerateOpen(false); setTab('calendar'); }}
          onSaved={reload}
          showToast={showToast}
        />
      )}

      {connectOpen && (
        <XConnectModal
          onClose={() => { setConnectOpen(false); setTab('calendar'); }}
          onConnected={reload}
          showToast={showToast}
        />
      )}
    </div>
  );
}
