export default function DetailModal({ item, onClose }) {
  if (!item) return null;

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
