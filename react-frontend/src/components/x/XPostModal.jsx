import { useState, useEffect, useRef } from 'react';
import { xCreatePost, xUpdatePost, xPostNow } from './xApi.js';

const MAX_LENGTH = 280;

// ISO 文字列 → <input type="datetime-local"> 用の "YYYY-MM-DDTHH:mm"
function toLocalInput(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d)) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromLocalInput(value) {
  if (!value) return null;
  const d = new Date(value);
  return isNaN(d) ? null : d.toISOString();
}

export default function XPostModal({ post, defaultDate, onClose, onSaved, showToast }) {
  const isEdit = Boolean(post && post.id);
  const [scheduledLocal, setScheduledLocal] = useState(() => toLocalInput(post?.scheduledAt || defaultDate));
  const [content, setContent] = useState(post?.content || '');
  const [imageUrl, setImageUrl] = useState(post?.imageUrl || null);
  const [imageFile, setImageFile] = useState(null);
  const [dragging, setDragging] = useState(false);
  const [saving, setSaving] = useState(false);
  const [postingNow, setPostingNow] = useState(false);
  const [aiLoading, setAiLoading] = useState(false);
  const fileInputRef = useRef(null);

  const busy = saving || postingNow;

  async function handleAiCorrect() {
    if (!content.trim()) {
      showToast?.('添削する本文がありません', 'error');
      return;
    }
    setAiLoading(true);
    try {
      const res = await fetch('/api/ai/correct', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text: content,
          instruction: 'X (Twitter) 投稿向けに、280文字以内・自然な口語・AIっぽさを消して書き直してください。語尾をバラけさせ、絵文字は0〜1個まで。',
        }),
      });
      if (!res.ok) throw new Error(`AI 添削に失敗: HTTP ${res.status}`);
      const data = await res.json();
      const next = (data.corrected || data.text || data.result || '').toString().trim();
      if (!next) throw new Error('AI 応答が空でした');
      setContent(next);
      showToast?.('AI 添削しました', 'success');
    } catch (err) {
      showToast?.(err.message || 'AI 添削に失敗しました', 'error');
    } finally {
      setAiLoading(false);
    }
  }

  useEffect(() => {
    return () => { if (imageUrl && imageUrl.startsWith('blob:')) URL.revokeObjectURL(imageUrl); };
  }, [imageUrl]);

  const remaining = MAX_LENGTH - content.length;
  const over = remaining < 0;
  const counterColor = over ? '#dc2626' : remaining <= 20 ? '#d97706' : '#6b7280';

  function pickFile(file) {
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      showToast?.('画像ファイルを選んでください', 'error');
      return;
    }
    setImageFile(file);
    setImageUrl(URL.createObjectURL(file));
  }

  function handleDrop(e) {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files?.[0];
    pickFile(file);
  }

  async function handleSave() {
    if (!scheduledLocal) {
      showToast?.('投稿日時を選んでください', 'error');
      return;
    }
    if (!content.trim()) {
      showToast?.('本文を入力してください', 'error');
      return;
    }
    if (over) {
      showToast?.('280文字を超えています', 'error');
      return;
    }
    setSaving(true);
    try {
      const payload = {
        scheduledAt: fromLocalInput(scheduledLocal),
        content: content.trim(),
        // 画像は本来 FormData で上げる。モック中は blob URL を載せておく。
        imageUrl: imageUrl || null,
      };
      if (isEdit) {
        await xUpdatePost(post.id, payload);
      } else {
        await xCreatePost(payload);
      }
      showToast?.(isEdit ? '更新しました' : '保存しました', 'success');
      onSaved?.();
      onClose?.();
    } catch (err) {
      showToast?.(err.message || '保存に失敗しました', 'error');
    } finally {
      setSaving(false);
    }
  }

  // 通常投稿（今すぐ投稿）: 保存 → その場で X API を直接叩いて即時投稿する。
  // 予約日時は不要。未指定なら現在時刻で保存し、post_now が即投稿する。
  async function handlePostNow() {
    if (!content.trim()) {
      showToast?.('本文を入力してください', 'error');
      return;
    }
    if (over) {
      showToast?.('280文字を超えています', 'error');
      return;
    }
    setPostingNow(true);
    try {
      const payload = {
        scheduledAt: fromLocalInput(scheduledLocal) || new Date().toISOString(),
        content: content.trim(),
        imageUrl: imageUrl || null,
      };
      const saved = isEdit ? await xUpdatePost(post.id, payload) : await xCreatePost(payload);
      const id = saved?.id ?? post?.id;
      const res = await xPostNow(id);
      if (res.ok) {
        showToast?.('X に投稿しました', 'success');
        onSaved?.();
        onClose?.();
      } else if (res.needsConnect) {
        showToast?.('X が未接続です。接続設定で auth_token / ct0 を登録してください', 'error');
        onSaved?.();
      } else {
        showToast?.(res.error || '投稿に失敗しました', 'error');
        onSaved?.();
      }
    } catch (err) {
      showToast?.(err.message || '投稿に失敗しました', 'error');
    } finally {
      setPostingNow(false);
    }
  }

  return (
    <div className="modal-overlay" onClick={(e) => { /* 背景クリックでは閉じない */ e.stopPropagation(); }}>
      <div className="modal" style={{ maxWidth: '560px' }} onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">{isEdit ? '予約ツイートを編集' : '予約ツイートを作成'}</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div className="modal-body">
          <div className="form-group">
            <label className="form-label">
              投稿日時 <span className="form-label-required">*</span>
            </label>
            <input
              className="form-input"
              type="datetime-local"
              value={scheduledLocal}
              onChange={(e) => setScheduledLocal(e.target.value)}
            />
          </div>

          <div className="form-group">
            <label className="form-label" style={{ justifyContent: 'space-between', display: 'flex', alignItems: 'center' }}>
              <span>本文 <span className="form-label-required">*</span></span>
              <span style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <button
                  type="button"
                  onClick={handleAiCorrect}
                  disabled={aiLoading || !content.trim()}
                  style={{
                    padding: '3px 10px', fontSize: '11px', fontWeight: 600,
                    background: aiLoading ? '#e9d5ff' : '#f5f0ff',
                    color: '#7c3aed', border: '1px solid #c4b5fd', borderRadius: '6px',
                    cursor: aiLoading || !content.trim() ? 'not-allowed' : 'pointer',
                    opacity: !content.trim() ? 0.5 : 1,
                  }}
                  title="AI で X 向けに添削（口語・280文字以内）"
                >
                  {aiLoading ? '✏️ 添削中…' : '✏️ AI 添削'}
                </button>
                <span style={{ color: counterColor, fontWeight: 700 }}>{remaining}</span>
              </span>
            </label>
            <textarea
              className="form-textarea"
              rows={8}
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder="280文字以内で。リンク・タグも本文と同じカウントです。"
              style={{ resize: 'vertical', minHeight: '160px' }}
            />
          </div>

          <div className="form-group">
            <label className="form-label">画像（任意）</label>
            <div
              onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
              onDragLeave={() => setDragging(false)}
              onDrop={handleDrop}
              onClick={() => fileInputRef.current?.click()}
              style={{
                border: `1.5px dashed ${dragging ? '#7c3aed' : '#ddd5f0'}`,
                background: dragging ? '#f5f0ff' : '#faf8ff',
                borderRadius: '10px',
                padding: '18px',
                textAlign: 'center',
                cursor: 'pointer',
                color: '#6b4fa0',
                fontSize: '13px',
                transition: 'all 0.15s',
              }}
            >
              {imageUrl ? (
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px', justifyContent: 'center' }}>
                  <img src={imageUrl} alt="" style={{ maxHeight: '120px', borderRadius: '6px', border: '1px solid #e2d9f3' }} />
                  <button
                    type="button"
                    className="btn btn-sm btn-secondary"
                    onClick={(e) => { e.stopPropagation(); setImageFile(null); setImageUrl(null); }}
                  >
                    画像を外す
                  </button>
                </div>
              ) : (
                <>ドラッグ＆ドロップ、またはクリックで画像を選択</>
              )}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                style={{ display: 'none' }}
                onChange={(e) => pickFile(e.target.files?.[0])}
              />
            </div>
            {imageFile && (
              <p style={{ fontSize: '11px', color: '#9878cc', margin: '4px 0 0' }}>
                {imageFile.name} ({Math.round(imageFile.size / 1024)} KB)
              </p>
            )}
          </div>
        </div>

        <div className="modal-footer">
          <button className="btn btn-secondary" onClick={onClose} disabled={busy}>キャンセル</button>
          <button
            className="btn btn-secondary"
            onClick={handleSave}
            disabled={busy || over}
            title="指定した日時に自動で投稿します（予約）"
          >
            {saving ? '保存中…' : isEdit ? '更新' : '予約保存'}
          </button>
          <button
            className="btn btn-primary"
            onClick={handlePostNow}
            disabled={busy || over}
            title="日時を待たず、今すぐ X に投稿します"
            style={{ background: '#16a34a', borderColor: '#16a34a' }}
          >
            {postingNow ? '投稿中…' : '今すぐ投稿'}
          </button>
        </div>
      </div>
    </div>
  );
}
