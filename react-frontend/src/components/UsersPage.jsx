import { useState, useEffect } from 'react';

export default function UsersPage({ showToast }) {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteRole, setInviteRole] = useState('viewer');
  const [inviting, setInviting] = useState(false);

  useEffect(() => { loadUsers(); }, []);

  async function loadUsers() {
    try {
      const res = await fetch('/api/admin/users');
      if (!res.ok) throw new Error('ユーザー一覧の取得に失敗');
      setUsers(await res.json());
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setLoading(false);
    }
  }

  async function handleInvite() {
    if (!inviteEmail.trim()) return showToast('メールアドレスを入力してください', 'error');
    setInviting(true);
    try {
      const res = await fetch('/api/admin/users/invite', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: inviteEmail, role: inviteRole }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      showToast(`${inviteEmail} を${inviteRole === 'editor' ? '投稿者' : '閲覧者'}として招待しました（パスワード: ${data.tempPassword}）`, 'success');
      setInviteEmail('');
      await loadUsers();
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setInviting(false);
    }
  }

  async function handleRoleChange(userId, newRole) {
    try {
      const res = await fetch(`/api/admin/users/${userId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ role: newRole }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      showToast('ロールを変更しました', 'success');
      await loadUsers();
    } catch (e) {
      showToast(e.message, 'error');
    }
  }

  async function handleDelete(user) {
    if (!confirm(`${user.email} を削除しますか？`)) return;
    try {
      const res = await fetch(`/api/admin/users/${user.id}`, { method: 'DELETE' });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      showToast(`${user.email} を削除しました`, 'success');
      await loadUsers();
    } catch (e) {
      showToast(e.message, 'error');
    }
  }

  const ROLE_LABELS = { admin: '管理者', editor: '投稿者', viewer: '閲覧者' };
  const ROLE_COLORS = { admin: '#dc2626', editor: '#2563eb', viewer: '#6b7280' };

  return (
    <div style={{ padding: '0 24px 24px', maxWidth: '900px' }}>
      <h2 style={{ fontSize: '18px', fontWeight: 700, color: '#2d1b52', marginBottom: '16px' }}>
        👥 ユーザー管理
      </h2>

      {/* 招待フォーム */}
      <div style={{ padding: '14px', background: '#f0f9ff', border: '1.5px solid #bae6fd', borderRadius: '10px', marginBottom: '20px' }}>
        <h3 style={{ fontSize: '14px', fontWeight: 600, margin: '0 0 10px', color: '#0369a1' }}>メンバー招待</h3>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center' }}>
          <input
            type="email"
            value={inviteEmail}
            onChange={(e) => setInviteEmail(e.target.value)}
            placeholder="メールアドレス"
            style={{ flex: 1, minWidth: '200px', padding: '8px 12px', border: '1px solid #d1d5db', borderRadius: '6px', fontSize: '13px' }}
          />
          <select
            value={inviteRole}
            onChange={(e) => setInviteRole(e.target.value)}
            style={{ padding: '8px 12px', border: '1px solid #d1d5db', borderRadius: '6px', fontSize: '13px' }}
          >
            <option value="editor">投稿者（編集・投稿可能）</option>
            <option value="viewer">閲覧者（閲覧のみ）</option>
          </select>
          <button
            className="btn btn-primary btn-sm"
            onClick={handleInvite}
            disabled={inviting}
            style={{ fontSize: '13px' }}
          >
            {inviting ? '招待中...' : '招待する'}
          </button>
        </div>
      </div>

      {/* ユーザー一覧 */}
      {loading ? (
        <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>読み込み中...</div>
      ) : (
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                <th style={{ textAlign: 'left', padding: '8px', color: '#6b7280' }}>ユーザー</th>
                <th style={{ textAlign: 'left', padding: '8px', color: '#6b7280' }}>メール</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>ロール</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>ログイン方法</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>操作</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                  <td style={{ padding: '10px 8px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      {u.avatarUrl ? (
                        <img src={u.avatarUrl} alt="" style={{ width: 28, height: 28, borderRadius: '50%' }} />
                      ) : (
                        <div style={{ width: 28, height: 28, borderRadius: '50%', background: '#e5e7eb', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '12px', color: '#6b7280' }}>
                          {(u.name || u.email)[0].toUpperCase()}
                        </div>
                      )}
                      <span style={{ fontWeight: 500 }}>{u.name || '-'}</span>
                    </div>
                  </td>
                  <td style={{ padding: '10px 8px', color: '#6b7280' }}>{u.email}</td>
                  <td style={{ padding: '10px 8px', textAlign: 'center' }}>
                    {u.role === 'admin' ? (
                      <span style={{ padding: '2px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 600, background: '#fee2e2', color: '#dc2626' }}>
                        管理者
                      </span>
                    ) : (
                      <select
                        value={u.role}
                        onChange={(e) => handleRoleChange(u.id, e.target.value)}
                        style={{ padding: '4px 8px', border: `1.5px solid ${ROLE_COLORS[u.role]}`, borderRadius: '6px', fontSize: '11px', fontWeight: 600, color: ROLE_COLORS[u.role], background: '#fff' }}
                      >
                        <option value="editor">投稿者</option>
                        <option value="viewer">閲覧者</option>
                      </select>
                    )}
                  </td>
                  <td style={{ padding: '10px 8px', textAlign: 'center', fontSize: '11px', color: '#9ca3af' }}>
                    {u.provider === 'google_oauth2' ? 'Google' : 'メール/PW'}
                  </td>
                  <td style={{ padding: '10px 8px', textAlign: 'center' }}>
                    {u.role !== 'admin' && (
                      <button
                        onClick={() => handleDelete(u)}
                        style={{ padding: '4px 10px', fontSize: '11px', color: '#dc2626', background: '#fee2e2', border: '1px solid #fca5a5', borderRadius: '6px', cursor: 'pointer' }}
                      >
                        削除
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
