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
  kokuchpro: { name: 'こくチーズ', icon: '🟠', url: 'https://www.kokuchpro.com/' },
  connpass:  { name: 'connpass', icon: '🔴', url: 'https://connpass.com/' },
  peatix:    { name: 'Peatix', icon: '🟡', url: 'https://peatix.com/' },
  techplay:  { name: 'TechPlay Owner', icon: '🔵', url: 'https://owner.techplay.jp/' },
  zoom:      { name: 'Zoom', icon: '🎥', url: 'https://zoom.us/' },
  lme:       { name: 'LME（エルメ）', icon: '🟢', url: 'https://page.line-and.me/' },
  tunagate:  { name: 'つなゲート', icon: '🤝', url: 'https://tunagate.com/', browserLogin: true, loginUrl: 'https://tunagate.com/auth/google?origin=https://tunagate.com' },
};

const STATUS_LABELS = {
  connected:    { text: '接続済み', color: '#16a34a', bg: '#dcfce7' },
  disconnected: { text: '未接続', color: '#6b7280', bg: '#f3f4f6' },
  env:          { text: 'ENV設定', color: '#9333ea', bg: '#f3e8ff' },
  testing:      { text: 'テスト中...', color: '#d97706', bg: '#fef3c7' },
  error:        { text: 'エラー', color: '#dc2626', bg: '#fee2e2' },
};

export default function ConnectionsPage({ showToast, onBack, inline = false }) {
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
    if (!formEmail || !formPassword) {
      showToast('メールアドレスとパスワードを入力してください', 'error');
      return;
    }
    try {
      await saveServiceConnection({ serviceName, email: formEmail, password: formPassword });
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

      {/* サービス一覧 */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {connections.map((conn) => {
          const label = SERVICE_LABELS[conn.serviceName] || { name: conn.serviceName, icon: '⚙️' };
          const status = STATUS_LABELS[testing === conn.serviceName ? 'testing' : conn.status] || STATUS_LABELS.disconnected;
          const isEditing = editingService === conn.serviceName;

          return (
            <div
              key={conn.serviceName}
              style={{
                border: '1.5px solid #e2e8f0',
                borderRadius: '12px',
                padding: '16px',
                background: '#fff',
                transition: 'border-color 0.2s',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: isEditing ? '12px' : 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <span style={{ fontSize: '20px' }}>{label.icon}</span>
                  <div>
                    <strong style={{ fontSize: '14px' }}>{label.name}</strong>
                    {conn.email && !isEditing && (
                      <div style={{ fontSize: '12px', color: '#6b7280' }}>
                        📧 {conn.email}
                      </div>
                    )}
                    {conn.email && !isEditing && (
                      <div style={{ fontSize: '11px', color: '#9ca3af', display: 'flex', alignItems: 'center', gap: '4px' }}>
                        🔑 {showPasswords[conn.serviceName] ? (conn.password || '••••••••') : '••••••••'}
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setShowPasswords(prev => ({ ...prev, [conn.serviceName]: !prev[conn.serviceName] }));
                          }}
                          style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '12px', padding: '0 2px' }}
                          title={showPasswords[conn.serviceName] ? 'パスワードを隠す' : 'パスワードを表示'}
                        >
                          {showPasswords[conn.serviceName] ? '🙈' : '👁️'}
                        </button>
                      </div>
                    )}
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span style={{
                    fontSize: '11px',
                    fontWeight: 600,
                    padding: '3px 10px',
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
                          style={{ fontSize: '11px', background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}
                        >
                          🌐 ログイン
                        </button>
                      )}
                      {conn.id && (
                        <button
                          className="btn btn-sm"
                          onClick={() => handleTest(conn)}
                          disabled={testing === conn.serviceName}
                          style={{ fontSize: '11px' }}
                        >
                          {testing === conn.serviceName ? '⏳' : '🔄'} テスト
                        </button>
                      )}
                      <button
                        className="btn btn-sm"
                        onClick={() => handleEdit(conn)}
                        style={{ fontSize: '11px' }}
                      >
                        ✏️ {conn.id ? '編集' : '接続する'}
                      </button>
                      {conn.id && (
                        <button
                          className="btn btn-sm"
                          onClick={() => handleDisconnect(conn)}
                          style={{ fontSize: '11px', color: '#dc2626' }}
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
                <div style={{ marginTop: '4px', fontSize: '11px', color: '#9ca3af' }}>
                  最終接続: {new Date(conn.lastConnectedAt).toLocaleString('ja-JP')}
                </div>
              )}

              {isEditing && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  <input
                    className="form-input"
                    type="email"
                    value={formEmail}
                    onChange={(e) => setFormEmail(e.target.value)}
                    placeholder="メールアドレス"
                    style={{ fontSize: '13px' }}
                  />
                  <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
                    <input
                      className="form-input"
                      type={showPasswords[`edit_${conn.serviceName}`] ? 'text' : 'password'}
                      value={formPassword}
                      onChange={(e) => setFormPassword(e.target.value)}
                      placeholder="パスワード"
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
