import { useState } from 'react';
import { xConnect, xTestConnection } from './xApi.js';

export default function XConnectModal({ onClose, onConnected, showToast }) {
  const [authToken, setAuthToken] = useState('');
  const [ct0, setCt0] = useState('');
  const [testing, setTesting] = useState(false);
  const [saving, setSaving] = useState(false);
  const [tested, setTested] = useState(null); // null | { ok, screenName, error }

  async function handleTest() {
    if (!authToken || !ct0) {
      showToast?.('auth_token と ct0 を両方入れてください', 'error');
      return;
    }
    setTesting(true);
    setTested(null);
    try {
      // 接続テストは「保存せずに値だけ検証」する想定。
      // 実装側で /api/x/test に body 付きで投げる仕様になったら xTestConnection を差し替える。
      const result = await xConnect({ authToken, ct0 });
      if (result?.ok) {
        const status = await xTestConnection();
        setTested({ ok: true, screenName: status.screenName || result.screenName });
      } else {
        setTested({ ok: false, error: result?.error || 'テストに失敗しました' });
      }
    } catch (err) {
      setTested({ ok: false, error: err.message });
    } finally {
      setTesting(false);
    }
  }

  async function handleSave() {
    if (!tested?.ok) {
      showToast?.('先に接続テストを通してください', 'error');
      return;
    }
    setSaving(true);
    try {
      const result = await xConnect({ authToken, ct0 });
      if (!result?.ok) throw new Error(result?.error || '保存に失敗しました');
      showToast?.('X セッションを保存しました', 'success');
      onConnected?.(result);
      onClose?.();
    } catch (err) {
      showToast?.(err.message, 'error');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-overlay">
      <div className="modal" style={{ maxWidth: '520px' }}>
        <div className="modal-header">
          <h2 className="modal-title">X セッションを取り込む</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div className="modal-body">
          <div style={{ background: '#faf8ff', border: '1.5px solid #e2d9f3', borderRadius: '10px', padding: '12px 14px', fontSize: '12px', color: '#3b1f6e', lineHeight: 1.7 }}>
            <strong>取得手順</strong>
            <ol style={{ margin: '6px 0 0 18px', padding: 0 }}>
              <li>x.com に普段使うアカウントでログイン</li>
              <li>DevTools（F12）→ Application タブ → Cookies → https://x.com</li>
              <li><code>auth_token</code> と <code>ct0</code> の Value をそれぞれコピー</li>
              <li>下の欄に貼り付けて「接続テスト」</li>
            </ol>
            <p style={{ margin: '8px 0 0', color: '#6b4fa0' }}>
              ※ 保存した Cookie はサーバ側でユーザーアカウントに紐づけて保管されます。共有 PC で取得した値は使わないでください。
            </p>
          </div>

          <div className="form-group">
            <label className="form-label">auth_token <span className="form-label-required">*</span></label>
            <input
              className="form-input"
              type="text"
              autoComplete="off"
              value={authToken}
              onChange={(e) => { setAuthToken(e.target.value.trim()); setTested(null); }}
              placeholder="長い英数字の文字列"
            />
          </div>

          <div className="form-group">
            <label className="form-label">ct0 <span className="form-label-required">*</span></label>
            <input
              className="form-input"
              type="text"
              autoComplete="off"
              value={ct0}
              onChange={(e) => { setCt0(e.target.value.trim()); setTested(null); }}
              placeholder="同じく Cookie の Value をそのまま"
            />
          </div>

          {tested && (
            <div style={{
              padding: '10px 12px',
              borderRadius: '8px',
              fontSize: '12px',
              background: tested.ok ? '#dcfce7' : '#fee2e2',
              color: tested.ok ? '#166534' : '#b91c1c',
              border: `1px solid ${tested.ok ? '#86efac' : '#fca5a5'}`,
            }}>
              {tested.ok
                ? `✅ 接続できました${tested.screenName ? `（@${tested.screenName}）` : ''}`
                : `❌ ${tested.error}`}
            </div>
          )}
        </div>

        <div className="modal-footer">
          <button className="btn btn-secondary" onClick={onClose} disabled={saving}>閉じる</button>
          <button className="btn btn-outline" onClick={handleTest} disabled={testing || saving}>
            {testing ? 'テスト中…' : '接続テスト'}
          </button>
          <button className="btn btn-primary" onClick={handleSave} disabled={!tested?.ok || saving}>
            {saving ? '保存中…' : '保存'}
          </button>
        </div>
      </div>
    </div>
  );
}
