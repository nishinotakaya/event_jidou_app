import { useState } from 'react';
import { xGenerateMonth, xCreatePost } from './xApi.js';

const BASE_THEME = 'プログラミング × 副業 × AI';

const TIME_SLOT_OPTIONS = [
  { key: 'morning', label: '朝（7:30）' },
  { key: 'noon',    label: '昼（12:15）' },
  { key: 'evening', label: '夜（20:00）' },
];

function todayIso() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function localDateTimeLabel(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d)) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export default function XGenerateModal({ onClose, onSaved, showToast }) {
  const [extraTheme, setExtraTheme] = useState('');
  const [startDate, setStartDate] = useState(todayIso());
  const [postsPerDay, setPostsPerDay] = useState(2);
  const [slots, setSlots] = useState(['morning', 'evening']);
  const [generating, setGenerating] = useState(false);
  const [drafts, setDrafts] = useState([]); // 編集可能なドラフト配列
  const [saving, setSaving] = useState(false);

  const toggleSlot = (key) => {
    setSlots((prev) => (prev.includes(key) ? prev.filter((s) => s !== key) : [...prev, key]));
  };

  async function handleGenerate() {
    if (!slots.length) {
      showToast?.('時間帯を1つ以上選んでください', 'error');
      return;
    }
    setGenerating(true);
    try {
      const theme = extraTheme ? `${BASE_THEME} / ${extraTheme}` : BASE_THEME;
      const result = await xGenerateMonth({ theme, startDate, postsPerDay, timeSlots: slots });
      const next = (result?.drafts || []).map((d, i) => ({
        ...d,
        key: d.id || `draft-${i}`,
      }));
      setDrafts(next);
      showToast?.(`${next.length}件のドラフトを生成しました`, 'success');
    } catch (err) {
      showToast?.(err.message || '生成に失敗しました', 'error');
    } finally {
      setGenerating(false);
    }
  }

  function updateDraft(key, patch) {
    setDrafts((prev) => prev.map((d) => (d.key === key ? { ...d, ...patch } : d)));
  }

  function removeDraft(key) {
    setDrafts((prev) => prev.filter((d) => d.key !== key));
  }

  async function handleSaveAll() {
    if (!drafts.length) return;
    setSaving(true);
    try {
      let saved = 0;
      let failed = 0;
      for (const draft of drafts) {
        try {
          await xCreatePost({
            scheduledAt: draft.scheduledAt,
            content: draft.content,
            imageUrl: draft.imageUrl || null,
          });
          saved++;
        } catch {
          failed++;
        }
      }
      showToast?.(`保存: ${saved} 件 / 失敗: ${failed} 件`, failed ? 'error' : 'success');
      onSaved?.();
      onClose?.();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-overlay">
      <div className="modal" style={{ maxWidth: '760px', maxHeight: '92vh' }}>
        <div className="modal-header">
          <h2 className="modal-title">AIで1ヶ月分まとめて作る</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div className="modal-body">
          {drafts.length === 0 && (
            <>
              <div className="form-group">
                <label className="form-label">テーマ（固定）</label>
                <div style={{ padding: '8px 12px', background: '#f5f0ff', border: '1.5px solid #e2d9f3', borderRadius: '8px', fontSize: '13px', color: '#3b1f6e', fontWeight: 600 }}>
                  {BASE_THEME}
                </div>
              </div>

              <div className="form-group">
                <label className="form-label">追加トピック・口調・避けたい表現など（任意）</label>
                <textarea
                  className="form-textarea"
                  rows={3}
                  value={extraTheme}
                  onChange={(e) => setExtraTheme(e.target.value)}
                  placeholder="例: 営業職から副業エンジニアになった人向け / 営業色を出しすぎない / 絵文字は控えめ"
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label">開始日</label>
                  <input
                    className="form-input"
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                  />
                </div>

                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label">1日あたりの投稿数</label>
                  <select
                    className="form-select"
                    value={postsPerDay}
                    onChange={(e) => setPostsPerDay(Number(e.target.value))}
                  >
                    <option value={2}>2 件</option>
                    <option value={3}>3 件</option>
                  </select>
                </div>
              </div>

              <div className="form-group">
                <label className="form-label">投稿時間帯（複数選択）</label>
                <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
                  {TIME_SLOT_OPTIONS.map((opt) => {
                    const active = slots.includes(opt.key);
                    return (
                      <button
                        key={opt.key}
                        type="button"
                        onClick={() => toggleSlot(opt.key)}
                        className="btn btn-sm"
                        style={{
                          background: active ? '#7c3aed' : '#faf8ff',
                          color: active ? '#fff' : '#6b4fa0',
                          border: `1.5px solid ${active ? '#7c3aed' : '#ddd5f0'}`,
                          fontWeight: 600,
                        }}
                      >
                        {opt.label}
                      </button>
                    );
                  })}
                </div>
              </div>
            </>
          )}

          {drafts.length > 0 && (
            <>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: '13px', color: '#3b1f6e', fontWeight: 700 }}>
                  プレビュー（{drafts.length} 件）
                </span>
                <button
                  className="btn btn-sm btn-secondary"
                  onClick={() => setDrafts([])}
                >
                  条件を変えて再生成
                </button>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {drafts.map((draft) => (
                  <div
                    key={draft.key}
                    style={{
                      border: '1.5px solid #e2d9f3',
                      borderRadius: '10px',
                      padding: '10px 12px',
                      background: '#fff',
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
                      <input
                        type="datetime-local"
                        className="form-input"
                        style={{ width: 'auto', flex: '0 0 200px' }}
                        value={(() => {
                          const d = new Date(draft.scheduledAt);
                          if (isNaN(d)) return '';
                          const pad = (n) => String(n).padStart(2, '0');
                          return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
                        })()}
                        onChange={(e) => updateDraft(draft.key, { scheduledAt: new Date(e.target.value).toISOString() })}
                      />
                      <span style={{ fontSize: '11px', color: '#9878cc' }}>{localDateTimeLabel(draft.scheduledAt)}</span>
                      <button
                        className="btn btn-sm btn-secondary"
                        style={{ marginLeft: 'auto', fontSize: '11px' }}
                        onClick={() => removeDraft(draft.key)}
                      >
                        除外
                      </button>
                    </div>
                    <textarea
                      className="form-textarea"
                      rows={3}
                      value={draft.content}
                      onChange={(e) => updateDraft(draft.key, { content: e.target.value })}
                      style={{ resize: 'vertical' }}
                    />
                    <div style={{ display: 'flex', justifyContent: 'flex-end', fontSize: '11px', color: draft.content.length > 280 ? '#dc2626' : '#9878cc' }}>
                      {draft.content.length} / 280
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        <div className="modal-footer">
          <button className="btn btn-secondary" onClick={onClose} disabled={generating || saving}>キャンセル</button>
          {drafts.length === 0 ? (
            <button className="btn btn-primary" onClick={handleGenerate} disabled={generating}>
              {generating ? '生成中…' : 'AI生成スタート'}
            </button>
          ) : (
            <button className="btn btn-primary" onClick={handleSaveAll} disabled={saving}>
              {saving ? '保存中…' : `${drafts.length}件まとめて保存`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
