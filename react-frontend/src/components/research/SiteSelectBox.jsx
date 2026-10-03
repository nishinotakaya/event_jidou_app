import { useState, useEffect, useRef } from 'react';

// 検索先サイトのセレクトボックス（複数選択）。
// サイトが増えるとチェックボックスの横並びでは検索条件が縦に伸びて他の条件が埋もれるので、
// 普段は「◯サイト」の1行に畳み、開いたときだけ一覧を出す。
// <select multiple> を使わないのは、Ctrl+クリックを知らないと複数選択できず、
// 選択中のサイトも色分けして見せられないため。
export default function SiteSelectBox({ sites, selectedKeys, onChange, disabled }) {
  const [open, setOpen] = useState(false);
  const boxRef = useRef(null);

  // 開いたまま他所をクリック／Escape で閉じる（開きっぱなしだと下の結果一覧が隠れる）
  useEffect(() => {
    if (!open) return undefined;
    function handlePointerDown(event) {
      if (boxRef.current && !boxRef.current.contains(event.target)) setOpen(false);
    }
    function handleKeyDown(event) {
      if (event.key === 'Escape') setOpen(false);
    }
    document.addEventListener('mousedown', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('mousedown', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [open]);

  const selectedSites = sites.filter((site) => selectedKeys.includes(site.key));
  const summary = selectedSites.length === 0
    ? 'サイトを選択'
    : selectedSites.length === sites.length
      ? `すべてのサイト（${sites.length}）`
      : selectedSites.length <= 3
        ? selectedSites.map((site) => site.label).join('・')
        : `${selectedSites.length}サイトを選択中`;

  function toggle(key) {
    onChange(selectedKeys.includes(key)
      ? selectedKeys.filter((selectedKey) => selectedKey !== key)
      : [...selectedKeys, key]);
  }

  return (
    <div ref={boxRef} style={{ position: 'relative' }}>
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((shown) => !shown)}
        aria-haspopup="listbox"
        aria-expanded={open}
        style={{
          display: 'flex', alignItems: 'center', gap: '8px', minWidth: 0, maxWidth: '100%',
          padding: '5px 10px', borderRadius: '8px', border: '1px solid #d1d5db',
          background: '#fff', color: selectedSites.length === 0 ? '#9ca3af' : '#1f2937',
          fontSize: '13px', cursor: disabled ? 'not-allowed' : 'pointer',
        }}
      >
        <span style={{ flex: 1, textAlign: 'left', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {summary}
        </span>
        <span style={{ color: '#9ca3af', fontSize: '10px' }}>{open ? '▲' : '▼'}</span>
      </button>

      {open && (
        <div
          role="listbox"
          aria-multiselectable="true"
          style={{
            position: 'absolute', zIndex: 20, top: 'calc(100% + 4px)', left: 0, minWidth: '280px', maxWidth: 'calc(100vw - 32px)',
            borderRadius: '10px', border: '1px solid #e5e7eb', background: '#fff',
            boxShadow: '0 8px 24px rgba(0,0,0,0.12)', padding: '8px', maxHeight: '320px', overflowY: 'auto',
          }}
        >
          <div style={{ display: 'flex', gap: '6px', padding: '2px 4px 8px', borderBottom: '1px solid #f3f4f6', marginBottom: '6px' }}>
            <button
              type="button"
              onClick={() => onChange(sites.map((site) => site.key))}
              style={{ padding: '2px 10px', borderRadius: '999px', border: '1px solid #c4b5fd', background: '#fff', color: '#6d28d9', fontSize: '11px', cursor: 'pointer' }}
            >
              すべて選択
            </button>
            <button
              type="button"
              onClick={() => onChange([])}
              style={{ padding: '2px 10px', borderRadius: '999px', border: '1px solid #d1d5db', background: '#fff', color: '#6b7280', fontSize: '11px', cursor: 'pointer' }}
            >
              すべて解除
            </button>
          </div>
          {sites.map((site) => {
            const selected = selectedKeys.includes(site.key);
            return (
              <label
                key={site.key}
                role="option"
                aria-selected={selected}
                title={site.note || ''}
                style={{ display: 'flex', alignItems: 'flex-start', gap: '8px', padding: '5px 6px', borderRadius: '6px', cursor: 'pointer', background: selected ? '#f5f3ff' : 'transparent' }}
              >
                <input type="checkbox" checked={selected} onChange={() => toggle(site.key)} style={{ marginTop: '2px' }} />
                <span style={{ minWidth: 0 }}>
                  <span style={{ color: site.color, fontWeight: 600, fontSize: '13px' }}>{site.label}</span>
                  {site.note && (
                    <span style={{ display: 'block', fontSize: '11px', color: '#9ca3af', lineHeight: 1.4 }}>{site.note}</span>
                  )}
                </span>
              </label>
            );
          })}
        </div>
      )}
    </div>
  );
}
