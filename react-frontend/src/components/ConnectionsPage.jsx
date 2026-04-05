import { useState, useEffect } from 'react';
import {
  fetchServiceConnections,
  saveServiceConnection,
  deleteServiceConnection,
  testServiceConnection,
  testNewServiceConnection,
  browserLogin,
} from '../api.js';

const SERVICE_LABELS = {
  kokuchpro: { name: 'こくチーズ', icon: '🟠', url: 'https://www.kokuchpro.com/', eventsUrl: 'https://www.kokuchpro.com/mypage/event/' },
  connpass:  { name: 'connpass', icon: '🔴', url: 'https://connpass.com/', eventsUrl: 'https://connpass.com/editmanage/' },
  peatix:    { name: 'Peatix', icon: '🟡', url: 'https://peatix.com/', eventsUrl: 'https://peatix.com/dashboard' },
  techplay:  { name: 'TechPlay Owner', icon: '🔵', url: 'https://owner.techplay.jp/', eventsUrl: 'https://owner.techplay.jp/dashboard' },
  zoom:      { name: 'Zoom', icon: '🎥', url: 'https://zoom.us/' },
  // lme:       { name: 'LME（エルメ）', icon: '🟢', url: 'https://page.line-and.me/' },
  tunagate:   { name: 'つなゲート', icon: '🤝', url: 'https://tunagate.com/', browserLogin: true, loginUrl: 'https://tunagate.com/auth/google?origin=https://tunagate.com', eventsUrl: 'https://tunagate.com/mypage' },
  doorkeeper: { name: 'Doorkeeper', icon: '🚪', url: 'https://www.doorkeeper.jp/', eventsUrl: 'https://manage.doorkeeper.jp/groups' },
  // seminars:        { name: 'セミナーズ', icon: '📢', url: 'https://seminars.jp/', eventsUrl: 'https://seminars.jp/user/profile/edit' },
  street_academy:  { name: 'ストアカ', icon: '🎓', url: 'https://www.street-academy.com/', eventsUrl: 'https://www.street-academy.com/dashboard/steachers/myclass' },
  eventregist:     { name: 'EventRegist', icon: '📋', url: 'https://eventregist.com/', eventsUrl: 'https://eventregist.com/eventlist' },
  passmarket:      { name: 'PassMarket', icon: '🅿️', url: 'https://passmarket.yahoo.co.jp/', browserLogin: true, loginUrl: 'https://passmarket.yahoo.co.jp/', eventsUrl: 'https://passmarket.yahoo.co.jp/manage/events/' },
  luma:            { name: 'Luma', icon: '✨', url: 'https://lu.ma/', browserLogin: true, loginUrl: 'https://lu.ma/signin', eventsUrl: 'https://lu.ma/home' },
  seminar_biz:     { name: 'セミナーBiZ', icon: '💼', url: 'https://seminar-biz.com/', eventsUrl: 'https://seminar-biz.com/company/dashboard' },
  jimoty:          { name: 'ジモティー', icon: '📍', url: 'https://jmty.jp/', browserLogin: true, loginUrl: 'https://jmty.jp/login', eventsUrl: 'https://jmty.jp/my/posts' },
  gmail:           { name: 'Gmail', icon: '📧', url: 'https://mail.google.com/', note: 'Googleログインで自動連携' },
  twitter:         { name: 'X (Twitter)', icon: '𝕏', url: 'https://x.com/', browserLogin: true, loginUrl: 'https://x.com/i/flow/login', eventsUrl: 'https://x.com/home' },
  instagram:       { name: 'Instagram', icon: '📸', url: 'https://www.instagram.com/', browserLogin: true, loginUrl: 'https://www.instagram.com/accounts/login/', eventsUrl: 'https://www.instagram.com/' },
  onclass:         { name: 'オンクラス', icon: '🎓', url: 'https://manager.the-online-class.com/' },
  github:          { name: 'GitHub', icon: '🐙', url: 'https://github.com/', tokenOnly: true, note: 'Personal Access Token（Classic, repoスコープ）' },
};

const STATUS_LABELS = {
  connected:    { text: '接続済み', color: '#16a34a', bg: '#dcfce7' },
  disconnected: { text: '未接続', color: '#6b7280', bg: '#f3f4f6' },
  env:          { text: 'ENV設定', color: '#9333ea', bg: '#f3e8ff' },
  testing:      { text: 'テスト中...', color: '#d97706', bg: '#fef3c7' },
  error:        { text: 'エラー', color: '#dc2626', bg: '#fee2e2' },
};

function maskEmail(email) {
  if (!email) return '';
  const [local, domain] = email.split('@');
  if (!domain) return '***';
  return local.substring(0, 3) + '***@' + domain;
}

export default function ConnectionsPage({ showToast, onBack, onGoToList, inline = false }) {
  const [connections, setConnections] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editingService, setEditingService] = useState(null);
  const [formEmail, setFormEmail] = useState('');
  const [formPassword, setFormPassword] = useState('');
  const [testing, setTesting] = useState(null);
  const [showPasswords, setShowPasswords] = useState({});
  const [currentUser, setCurrentUser] = useState(null);

  useEffect(() => {
    loadConnections();
    fetch('/api/current_user').then(r => r.json()).then(d => {
      if (d && d.id) setCurrentUser(d);
    }).catch(() => {});
  }, []);

  async function loadConnections() {
    try {
      const data = await fetchServiceConnections();
      setConnections(data);
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setLoading(false);
    }
  }

  function handleEdit(conn) {
    setEditingService(conn.serviceName);
    setFormEmail(conn.email || '');
    setFormPassword(conn.password || '');
  }

  function handleCancelEdit() {
    setEditingService(null);
    setFormEmail('');
    setFormPassword('');
  }

  async function handleSave(serviceName) {
    const isToken = SERVICE_LABELS[serviceName]?.tokenOnly;
    if (!isToken && !formEmail) {
      showToast('メールアドレスを入力してください', 'error');
      return;
    }
    if (!formPassword) {
      showToast(isToken ? 'トークンを入力してください' : 'パスワードを入力してください', 'error');
      return;
    }
    try {
      await saveServiceConnection({ serviceName, email: isToken ? serviceName : formEmail, password: formPassword });
      showToast('接続情報を保存しました', 'success');
      setEditingService(null);
      setFormEmail('');
      setFormPassword('');
      await loadConnections();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  async function handleTest(conn) {
    setTesting(conn.serviceName);
    try {
      if (conn.id) {
        await testServiceConnection(conn.id);
        showToast(`${SERVICE_LABELS[conn.serviceName]?.name} の接続テストを開始しました`, 'success');
      } else if (editingService === conn.serviceName && formEmail && formPassword) {
        await testNewServiceConnection({
          serviceName: conn.serviceName,
          email: formEmail,
          password: formPassword,
        });
        showToast('接続テストを開始しました（保存+テスト）', 'success');
        setEditingService(null);
        setFormEmail('');
        setFormPassword('');
      } else {
        showToast('先に接続情報を入力してください', 'error');
        setTesting(null);
        return;
      }
      // ポーリングでステータスを更新
      setTimeout(async () => {
        await loadConnections();
        setTesting(null);
      }, 10000);
    } catch (err) {
      showToast(err.message, 'error');
      setTesting(null);
    }
  }

  async function handleDisconnect(conn) {
    if (!conn.id) return;
    try {
      await deleteServiceConnection(conn.id);
      showToast(`${SERVICE_LABELS[conn.serviceName]?.name} を切断しました`, 'success');
      await loadConnections();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '40px' }}>
        <span className="spinner" /> 読み込み中...
      </div>
    );
  }

  return (
    <div style={{ maxWidth: inline ? '100%' : '900px', width: '100%', margin: '0 auto', padding: inline ? '0' : '20px' }}>
      {!inline && (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px' }}>
          <h2 style={{ margin: 0, fontSize: '20px' }}>
            🔗 サービス接続管理
          </h2>
          {onBack && (
            <button className="btn btn-secondary" onClick={onBack} style={{ fontSize: '13px' }}>
              ← 戻る
            </button>
          )}
        </div>
      )}

      {/* Google ログイン / ユーザー情報 */}
      <div style={{
        padding: '16px',
        marginBottom: '16px',
        background: currentUser ? '#f0fdf4' : '#f0f7ff',
        border: `1.5px solid ${currentUser ? '#bbf7d0' : '#bfdbfe'}`,
        borderRadius: '12px',
      }}>
        {currentUser ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            {currentUser.avatarUrl && (
              <img
                src={currentUser.avatarUrl}
                alt=""
                style={{ width: 36, height: 36, borderRadius: '50%' }}
              />
            )}
            <div style={{ flex: 1 }}>
              <strong>{currentUser.name || currentUser.email}</strong>
              <p style={{ margin: '2px 0 0', fontSize: '12px', color: '#6b7280' }}>
                {currentUser.email} — Googleアカウント連携済み
              </p>
            </div>
            <button
              className="btn btn-secondary"
              style={{ fontSize: '12px' }}
              onClick={async () => {
                await fetch('/api/logout', { method: 'DELETE' });
                setCurrentUser(null);
                showToast('ログアウトしました', 'success');
              }}
            >
              ログアウト
            </button>
          </div>
        ) : (
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <span style={{ fontSize: '24px' }}>G</span>
            <div style={{ flex: 1 }}>
              <strong>Googleアカウント連携</strong>
              <p style={{ margin: '4px 0 0', fontSize: '12px', color: '#6b7280' }}>
                Googleでログインすると、設定がアカウントに紐付けられます
              </p>
            </div>
            <button
              className="btn btn-primary"
              style={{ fontSize: '13px' }}
              onClick={() => { window.location.href = '/auth/google_oauth2'; }}
            >
              Googleでログイン
            </button>
          </div>
        )}
      </div>

      {/* サービス一覧（コンパクトグリッド） */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '8px' }}>
        {connections.map((conn) => {
          const label = SERVICE_LABELS[conn.serviceName] || { name: conn.serviceName, icon: '⚙️' };
          const status = STATUS_LABELS[testing === conn.serviceName ? 'testing' : conn.status] || STATUS_LABELS.disconnected;
          const isEditing = editingService === conn.serviceName;
          const isConnected = conn.status === 'connected' || conn.status === 'env';
          const borderColor = isConnected ? '#86efac' : conn.status === 'error' ? '#fca5a5' : '#e2e8f0';
          const bgColor = isConnected ? '#f0fdf4' : conn.status === 'error' ? '#fef2f2' : '#fff';

          return (
            <div
              key={conn.serviceName}
              style={{
                border: `1.5px solid ${borderColor}`,
                borderRadius: '8px',
                padding: '10px 12px',
                background: bgColor,
                transition: 'border-color 0.2s',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '6px', flexWrap: 'wrap', marginBottom: isEditing ? '8px' : 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', minWidth: 0 }}>
                  <span style={{ fontSize: '16px' }}>{label.icon}</span>
                  <div style={{ minWidth: 0 }}>
                    <strong style={{ fontSize: '12px' }}>{label.name}</strong>
                    {conn.email && !isEditing && (
                      <div style={{ fontSize: '10px', color: '#6b7280', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '4px' }}>
                        <span>{showPasswords[`email_${conn.serviceName}`] ? conn.email : maskEmail(conn.email)}</span>
                        {currentUser && (
                          <button
                            onClick={(e) => { e.stopPropagation(); setShowPasswords(prev => ({ ...prev, [`email_${conn.serviceName}`]: !prev[`email_${conn.serviceName}`] })); }}
                            style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '11px', padding: 0, lineHeight: 1 }}
                            title={showPasswords[`email_${conn.serviceName}`] ? '隠す' : '表示'}
                          >
                            {showPasswords[`email_${conn.serviceName}`] ? '🙈' : '👁️'}
                          </button>
                        )}
                      </div>
                    )}
                    {!isEditing && (
                      <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                        {label.eventsUrl && (
                          <a href={label.eventsUrl} target="_blank" rel="noopener noreferrer"
                            style={{ fontSize: '10px', color: '#3b82f6', textDecoration: 'none' }}
                            onClick={(e) => e.stopPropagation()}>📋 サイト一覧</a>
                        )}
                        {onGoToList && (
                          <button
                            onClick={(e) => { e.stopPropagation(); onGoToList(); }}
                            style={{ fontSize: '10px', color: '#7c3aed', background: 'none', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}
                          >📂 イベント一覧へ</button>
                        )}
                      </div>
                    )}
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '4px', flexWrap: 'wrap', flexShrink: 0 }}>
                  <span style={{
                    fontSize: '9px',
                    fontWeight: 600,
                    padding: '2px 6px',
                    borderRadius: '999px',
                    color: status.color,
                    background: status.bg,
                  }}>
                    {status.text}
                  </span>

                  {!isEditing && (
                    <>
                      {label.browserLogin && (
                        <button
                          className="btn btn-sm"
                          onClick={async () => {
                            // 1. 新タブでつなゲートGoogleログインを開く
                            const loginUrl = label.loginUrl || `${label.url}users/sign_in`;
                            const w = window.open(loginUrl, 'tunagate_login', 'width=600,height=700');
                            showToast(`${label.name} にログインしてください。完了したらウィンドウを閉じてください。`, 'success');

                            // 2. ウィンドウが閉じたらCookie抽出スクリプトを実行
                            const poll = setInterval(async () => {
                              if (w && w.closed) {
                                clearInterval(poll);
                                showToast('ログイン完了を確認中...', 'info');
                                try {
                                  const res = await fetch('/api/service_connections/capture_session', {
                                    method: 'POST',
                                    headers: { 'Content-Type': 'application/json' },
                                    body: JSON.stringify({ service_name: conn.serviceName }),
                                  });
                                  const data = await res.json();
                                  if (data.ok) {
                                    showToast(`${label.name} のセッション保存完了！`, 'success');
                                  } else {
                                    showToast(data.error || 'セッション保存に失敗', 'error');
                                  }
                                } catch (err) { showToast(err.message, 'error'); }
                                await loadConnections();
                              }
                            }, 1000);
                          }}
                          style={{ fontSize: '10px', padding: '2px 6px', background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}
                        >
                          🌐 ログイン
                        </button>
                      )}
                      {conn.id && (
                        <button
                          className="btn btn-sm"
                          onClick={() => handleTest(conn)}
                          disabled={testing === conn.serviceName}
                          style={{ fontSize: '10px' }}
                        >
                          {testing === conn.serviceName ? '⏳' : '🔄'} テスト
                        </button>
                      )}
                      <button
                        className="btn btn-sm"
                        onClick={() => handleEdit(conn)}
                        style={{ fontSize: '10px' }}
                      >
                        ✏️ {conn.id ? '編集' : '接続する'}
                      </button>
                      {conn.id && (
                        <button
                          className="btn btn-sm"
                          onClick={() => handleDisconnect(conn)}
                          style={{ fontSize: '10px', color: '#dc2626' }}
                        >
                          切断
                        </button>
                      )}
                    </>
                  )}
                </div>
              </div>

              {conn.errorMessage && !isEditing && (
                <div style={{ marginTop: '8px', padding: '6px 10px', background: '#fee2e2', borderRadius: '6px', fontSize: '12px', color: '#991b1b' }}>
                  {conn.errorMessage}
                </div>
              )}

              {conn.lastConnectedAt && !isEditing && (
                <div style={{ marginTop: '4px', fontSize: '10px', color: '#9ca3af' }}>
                  最終接続: {new Date(conn.lastConnectedAt).toLocaleString('ja-JP')}
                </div>
              )}

              {isEditing && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  {!label.tokenOnly && (
                    <input
                      className="form-input"
                      type="email"
                      value={formEmail}
                      onChange={(e) => setFormEmail(e.target.value)}
                      placeholder="メールアドレス"
                      style={{ fontSize: '13px' }}
                    />
                  )}
                  {label.note && (
                    <p style={{ margin: 0, fontSize: '10px', color: '#9ca3af' }}>{label.note}</p>
                  )}
                  <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
                    <input
                      className="form-input"
                      type={showPasswords[`edit_${conn.serviceName}`] ? 'text' : 'password'}
                      value={formPassword}
                      onChange={(e) => setFormPassword(e.target.value)}
                      placeholder={label.tokenOnly ? 'トークン' : 'パスワード'}
                      style={{ fontSize: '13px', flex: 1 }}
                    />
                    <button
                      type="button"
                      onClick={() => setShowPasswords(prev => ({ ...prev, [`edit_${conn.serviceName}`]: !prev[`edit_${conn.serviceName}`] }))}
                      style={{ background: 'none', border: '1px solid #e2e8f0', borderRadius: '6px', padding: '6px 8px', cursor: 'pointer', fontSize: '14px' }}
                      title={showPasswords[`edit_${conn.serviceName}`] ? 'パスワードを隠す' : 'パスワードを表示'}
                    >
                      {showPasswords[`edit_${conn.serviceName}`] ? '🙈' : '👁️'}
                    </button>
                  </div>
                  <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                    <button className="btn btn-secondary btn-sm" onClick={handleCancelEdit} style={{ fontSize: '12px' }}>
                      キャンセル
                    </button>
                    <button
                      className="btn btn-sm"
                      onClick={() => handleTest({ ...conn, serviceName: conn.serviceName })}
                      style={{ fontSize: '12px', background: '#f59e0b', color: '#fff' }}
                    >
                      🔄 保存+テスト
                    </button>
                    <button
                      className="btn btn-primary btn-sm"
                      onClick={() => handleSave(conn.serviceName)}
                      style={{ fontSize: '12px' }}
                    >
                      💾 保存
                    </button>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
