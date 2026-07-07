import { useState, useEffect } from 'react';
import {
  listMeetingNotifications,
  createMeetingNotification,
  updateMeetingNotification,
  deleteMeetingNotification,
  sendMeetingNotificationNow,
  previewMeetingNotification,
  fetchOnclassChannels,
  fetchZoomSettings,
} from '../api.js';

const WEEKDAY_LABELS = ['日', '月', '火', '水', '木', '金', '土'];

export default function MeetingNotificationsPage({ showToast }) {
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(true);

  // 追加/編集モーダル
  const [editingItem, setEditingItem] = useState(null); // null=閉じる, {}=新規, item=編集
  const [formName, setFormName] = useState('');
  const [formChannel, setFormChannel] = useState('');
  const [formZoomUrl, setFormZoomUrl] = useState('');
  const [formMeetingId, setFormMeetingId] = useState('');
  const [formPasscode, setFormPasscode] = useState('');
  const [formWeekday, setFormWeekday] = useState(0);
  const [formStartTime, setFormStartTime] = useState('22:00');
  const [formEndTime, setFormEndTime] = useState('22:30');
  const [formNotifyTime, setFormNotifyTime] = useState('19:30');
  const [formEnabled, setFormEnabled] = useState(true);
  const [saving, setSaving] = useState(false);

  // チャンネル選択肢（取得失敗時はテキスト入力にフォールバック）
  const [channelOptions, setChannelOptions] = useState(null); // null=未取得
  const [channelsLoading, setChannelsLoading] = useState(false);
  const [channelsFailed, setChannelsFailed] = useState(false);

  // 保存済みZoom設定（選択するとzoomUrl/meetingId/passcodeを自動入力）
  const [zoomSettings, setZoomSettings] = useState(null); // null=未取得
  const [zoomSettingsLoading, setZoomSettingsLoading] = useState(false);
  const [selectedZoomSettingId, setSelectedZoomSettingId] = useState('');

  // プレビュー
  const [previewItem, setPreviewItem] = useState(null);
  const [previewText, setPreviewText] = useState('');
  const [previewLoading, setPreviewLoading] = useState(false);

  // 今すぐ送信中の行
  const [sendingId, setSendingId] = useState(null);

  useEffect(() => { loadNotifications(); }, []);

  async function loadNotifications() {
    setLoading(true);
    try {
      const data = await listMeetingNotifications();
      setNotifications(data);
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setLoading(false);
    }
  }

  async function loadChannelsIfNeeded() {
    if (channelOptions !== null || channelsFailed || channelsLoading) return;
    setChannelsLoading(true);
    try {
      const data = await fetchOnclassChannels();
      setChannelOptions(data.channels || []);
    } catch (e) {
      setChannelsFailed(true);
      showToast(`チャンネル一覧の取得に失敗しました（手入力してください）: ${e.message}`, 'error');
    } finally {
      setChannelsLoading(false);
    }
  }

  async function loadZoomSettingsIfNeeded() {
    if (zoomSettings !== null || zoomSettingsLoading) return;
    setZoomSettingsLoading(true);
    try {
      const data = await fetchZoomSettings();
      setZoomSettings(data || []);
    } catch (e) {
      setZoomSettings([]);
      showToast(`Zoom設定の取得に失敗しました: ${e.message}`, 'error');
    } finally {
      setZoomSettingsLoading(false);
    }
  }

  function handleOpenNew() {
    setEditingItem({});
    setFormName('');
    setFormChannel('');
    setFormZoomUrl('');
    setFormMeetingId('');
    setFormPasscode('');
    setFormWeekday(0);
    setFormStartTime('22:00');
    setFormEndTime('22:30');
    setFormNotifyTime('19:30');
    setFormEnabled(true);
    setSelectedZoomSettingId('');
    loadChannelsIfNeeded();
    loadZoomSettingsIfNeeded();
  }

  function handleOpenEdit(item) {
    setEditingItem(item);
    setFormName(item.name || '');
    setFormChannel(item.onclassChannel || '');
    setFormZoomUrl(item.zoomUrl || '');
    setFormMeetingId(item.meetingId || '');
    setFormPasscode(item.passcode || '');
    setFormWeekday(item.weekday ?? 0);
    setFormStartTime(item.startTime || '');
    setFormEndTime(item.endTime || '');
    setFormNotifyTime(item.notifyTime || '');
    setFormEnabled(!!item.enabled);
    setSelectedZoomSettingId('');
    loadChannelsIfNeeded();
    loadZoomSettingsIfNeeded();
  }

  function handleCancelForm() {
    setEditingItem(null);
  }

  async function handleSubmit() {
    if (!formName.trim()) return showToast('チーム名を入力してください', 'error');
    if (!formChannel.trim()) return showToast('投稿先チャンネルを入力してください', 'error');
    if (!formZoomUrl.trim()) return showToast('Zoom URLを入力してください', 'error');
    if (!formStartTime) return showToast('ミーティング開始時刻を入力してください', 'error');
    if (!formNotifyTime) return showToast('通知時刻を入力してください', 'error');

    const payload = {
      name: formName.trim(),
      onclassChannel: formChannel.trim(),
      zoomUrl: formZoomUrl.trim(),
      meetingId: formMeetingId.trim(),
      passcode: formPasscode.trim(),
      weekday: Number(formWeekday),
      startTime: formStartTime,
      endTime: formEndTime,
      notifyTime: formNotifyTime,
      enabled: formEnabled,
    };

    setSaving(true);
    try {
      if (editingItem && editingItem.id) {
        await updateMeetingNotification(editingItem.id, payload);
        showToast('定例ミーティング通知を更新しました', 'success');
      } else {
        await createMeetingNotification(payload);
        showToast('定例ミーティング通知を追加しました', 'success');
      }
      setEditingItem(null);
      await loadNotifications();
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setSaving(false);
    }
  }

  async function handleToggleEnabled(item) {
    try {
      const updated = await updateMeetingNotification(item.id, {
        name: item.name,
        onclassChannel: item.onclassChannel,
        zoomUrl: item.zoomUrl,
        meetingId: item.meetingId,
        passcode: item.passcode,
        weekday: item.weekday,
        startTime: item.startTime,
        endTime: item.endTime,
        notifyTime: item.notifyTime,
        enabled: !item.enabled,
      });
      setNotifications((prev) => prev.map((n) => (n.id === updated.id ? updated : n)));
      showToast(updated.enabled ? '有効にしました' : '無効にしました', 'success');
    } catch (e) {
      showToast(e.message, 'error');
    }
  }

  async function handleDelete(item) {
    if (!confirm(`「${item.name}」を削除しますか？この操作は取り消せません。`)) return;
    try {
      await deleteMeetingNotification(item.id);
      showToast('削除しました', 'success');
      await loadNotifications();
    } catch (e) {
      showToast(e.message, 'error');
    }
  }

  async function handlePreview(item) {
    setPreviewItem(item);
    setPreviewText('');
    setPreviewLoading(true);
    try {
      const data = await previewMeetingNotification(item.id);
      setPreviewText(data.text);
    } catch (e) {
      showToast(e.message, 'error');
      setPreviewItem(null);
    } finally {
      setPreviewLoading(false);
    }
  }

  async function handleSendNow(item) {
    if (!confirm(`「${item.name}」の定例ミーティング通知を今すぐオンクラス（${item.onclassChannel}）へ投稿します。よろしいですか？`)) return;
    setSendingId(item.id);
    try {
      await sendMeetingNotificationNow(item.id);
      showToast(`送信しました: ${item.name}`, 'success');
      await loadNotifications();
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setSendingId(null);
    }
  }

  return (
    <div style={{ padding: '0 24px 24px', maxWidth: '1100px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '16px' }}>
        <h2 style={{ fontSize: '18px', fontWeight: 700, color: '#2d1b52', margin: 0 }}>
          📅 定例ミーティング通知
        </h2>
        <button className="btn btn-primary btn-sm" onClick={handleOpenNew}>
          + 追加
        </button>
      </div>

      {loading ? (
        <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>
          <span className="spinner" /> 読み込み中...
        </div>
      ) : notifications.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af', fontSize: '13px' }}>
          定例ミーティング通知がまだ登録されていません。「+ 追加」から作成してください。
        </div>
      ) : (
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                <th style={{ textAlign: 'left', padding: '8px', color: '#6b7280' }}>チーム名</th>
                <th style={{ textAlign: 'left', padding: '8px', color: '#6b7280' }}>投稿先チャンネル</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>曜日</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>ミーティング時刻</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>通知時刻</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>有効</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>最終送信日</th>
                <th style={{ textAlign: 'center', padding: '8px', color: '#6b7280' }}>操作</th>
              </tr>
            </thead>
            <tbody>
              {notifications.map((item) => (
                <tr key={item.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                  <td style={{ padding: '10px 8px', fontWeight: 500 }}>{item.name}</td>
                  <td style={{ padding: '10px 8px', color: '#6b7280' }}>{item.onclassChannel}</td>
                  <td style={{ padding: '10px 8px', textAlign: 'center' }}>{WEEKDAY_LABELS[item.weekday]}</td>
                  <td style={{ padding: '10px 8px', textAlign: 'center' }}>
                    {item.startTime}{item.endTime ? `〜${item.endTime}` : ''}
                  </td>
                  <td style={{ padding: '10px 8px', textAlign: 'center' }}>{item.notifyTime}</td>
                  <td style={{ padding: '10px 8px', textAlign: 'center' }}>
                    <button
                      onClick={() => handleToggleEnabled(item)}
                      style={{
                        padding: '2px 10px',
                        borderRadius: '12px',
                        fontSize: '11px',
                        fontWeight: 600,
                        border: 'none',
                        cursor: 'pointer',
                        color: item.enabled ? '#16a34a' : '#6b7280',
                        background: item.enabled ? '#dcfce7' : '#f3f4f6',
                      }}
                      title={item.enabled ? 'クリックで無効化' : 'クリックで有効化'}
                    >
                      {item.enabled ? '有効' : '無効'}
                    </button>
                  </td>
                  <td style={{ padding: '10px 8px', textAlign: 'center', fontSize: '11px', color: '#9ca3af' }}>
                    {item.lastSentOn ? new Date(item.lastSentOn).toLocaleDateString('ja-JP') : '未送信'}
                  </td>
                  <td style={{ padding: '10px 8px', textAlign: 'center' }}>
                    <div style={{ display: 'flex', gap: '4px', justifyContent: 'center', flexWrap: 'wrap' }}>
                      <button className="btn btn-sm" onClick={() => handlePreview(item)} style={{ fontSize: '11px' }}>
                        👀 プレビュー
                      </button>
                      <button
                        className="btn btn-sm"
                        onClick={() => handleSendNow(item)}
                        disabled={sendingId === item.id}
                        style={{ fontSize: '11px', background: '#f59e0b', color: '#fff' }}
                      >
                        {sendingId === item.id ? '⏳ 送信中...' : '🚀 今すぐ送信'}
                      </button>
                      <button className="btn btn-sm" onClick={() => handleOpenEdit(item)} style={{ fontSize: '11px' }}>
                        ✏️ 編集
                      </button>
                      <button
                        onClick={() => handleDelete(item)}
                        style={{ padding: '4px 10px', fontSize: '11px', color: '#dc2626', background: '#fee2e2', border: '1px solid #fca5a5', borderRadius: '6px', cursor: 'pointer' }}
                      >
                        削除
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* 追加/編集モーダル */}
      {editingItem !== null && (
        <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget && !saving) handleCancelForm(); }}>
          <div className="modal" style={{ maxWidth: '520px' }}>
            <div className="modal-header">
              <h2 className="modal-title">
                {editingItem.id ? '定例ミーティング通知の編集' : '定例ミーティング通知の追加'}
              </h2>
              <button className="modal-close" onClick={handleCancelForm}>✕</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label className="form-label">チーム名 <span className="form-label-required">*</span></label>
                <input
                  className="form-input"
                  value={formName}
                  onChange={(e) => setFormName(e.target.value)}
                  placeholder="例: Aチーム（元基礎編）"
                />
              </div>

              <div className="form-group">
                <label className="form-label">投稿先チャンネル <span className="form-label-required">*</span></label>
                {channelsFailed ? (
                  <input
                    className="form-input"
                    value={formChannel}
                    onChange={(e) => setFormChannel(e.target.value)}
                    placeholder="チャンネル名を入力"
                  />
                ) : channelOptions === null ? (
                  <div style={{ fontSize: '12px', color: '#9ca3af', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <span className="spinner" style={{ width: 12, height: 12 }} /> チャンネル一覧を取得中...
                  </div>
                ) : (
                  <select
                    className="form-select"
                    value={formChannel}
                    onChange={(e) => setFormChannel(e.target.value)}
                  >
                    <option value="">-- 選択してください --</option>
                    {channelOptions.map((c) => (
                      <option key={c.id} value={c.name}>{c.name}</option>
                    ))}
                    {formChannel && !channelOptions.some((c) => c.name === formChannel) && (
                      <option value={formChannel}>{formChannel}（現在の設定）</option>
                    )}
                  </select>
                )}
              </div>

              <div className="form-group">
                <label className="form-label">Zoom設定から選択</label>
                {zoomSettingsLoading ? (
                  <div style={{ fontSize: '12px', color: '#9ca3af', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <span className="spinner" style={{ width: 12, height: 12 }} /> Zoom設定を取得中...
                  </div>
                ) : (
                  <select
                    className="form-select"
                    value={selectedZoomSettingId}
                    onChange={(e) => {
                      const settingId = e.target.value;
                      setSelectedZoomSettingId(settingId);
                      if (!settingId) return;
                      const setting = (zoomSettings || []).find((z) => String(z.id) === settingId);
                      if (setting) {
                        setFormZoomUrl(setting.zoomUrl || '');
                        setFormMeetingId(setting.meetingId || '');
                        setFormPasscode(setting.passcode || '');
                      }
                    }}
                  >
                    <option value="">-- 保存済みZoom設定を選択（任意） --</option>
                    {(zoomSettings || []).map((z) => (
                      <option key={z.id} value={z.id}>{z.label || z.title || `設定#${z.id}`}</option>
                    ))}
                  </select>
                )}
              </div>

              <div className="form-group">
                <label className="form-label">Zoom URL <span className="form-label-required">*</span></label>
                <input
                  className="form-input"
                  value={formZoomUrl}
                  onChange={(e) => setFormZoomUrl(e.target.value)}
                  placeholder="https://zoom.us/j/..."
                />
              </div>

              <div className="form-row">
                <div className="form-group">
                  <label className="form-label">ミーティングID</label>
                  <input
                    className="form-input"
                    value={formMeetingId}
                    onChange={(e) => setFormMeetingId(e.target.value)}
                    placeholder="例: 889 9861 5545"
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">パスコード</label>
                  <input
                    className="form-input"
                    value={formPasscode}
                    onChange={(e) => setFormPasscode(e.target.value)}
                  />
                </div>
              </div>

              <div className="form-group">
                <label className="form-label">曜日</label>
                <select
                  className="form-select"
                  value={formWeekday}
                  onChange={(e) => setFormWeekday(Number(e.target.value))}
                >
                  {WEEKDAY_LABELS.map((label, weekdayNumber) => (
                    <option key={weekdayNumber} value={weekdayNumber}>{label}曜日</option>
                  ))}
                </select>
              </div>

              <div className="form-row-3">
                <div className="form-group">
                  <label className="form-label">開始時刻 <span className="form-label-required">*</span></label>
                  <input
                    className="form-input"
                    type="time"
                    value={formStartTime}
                    onChange={(e) => setFormStartTime(e.target.value)}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">終了時刻</label>
                  <input
                    className="form-input"
                    type="time"
                    value={formEndTime}
                    onChange={(e) => setFormEndTime(e.target.value)}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">通知時刻 <span className="form-label-required">*</span></label>
                  <input
                    className="form-input"
                    type="time"
                    value={formNotifyTime}
                    onChange={(e) => setFormNotifyTime(e.target.value)}
                  />
                </div>
              </div>

              <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '13px', color: '#374151', cursor: 'pointer' }}>
                <input
                  type="checkbox"
                  checked={formEnabled}
                  onChange={(e) => setFormEnabled(e.target.checked)}
                />
                有効にする（自動通知を送信する）
              </label>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={handleCancelForm} disabled={saving}>
                キャンセル
              </button>
              <button className="btn btn-primary" onClick={handleSubmit} disabled={saving}>
                {saving ? '保存中...' : '保存'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* プレビューモーダル */}
      {previewItem && (
        <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) setPreviewItem(null); }}>
          <div className="modal" style={{ maxWidth: '520px' }}>
            <div className="modal-header">
              <h2 className="modal-title">プレビュー: {previewItem.name}</h2>
              <button className="modal-close" onClick={() => setPreviewItem(null)}>✕</button>
            </div>
            <div className="modal-body">
              {previewLoading ? (
                <div style={{ textAlign: 'center', padding: '20px', color: '#9ca3af' }}>
                  <span className="spinner" /> 読み込み中...
                </div>
              ) : (
                <div style={{ whiteSpace: 'pre-wrap', fontSize: '13px', lineHeight: 1.6, background: '#faf8ff', border: '1px solid #ddd5f0', borderRadius: '8px', padding: '12px' }}>
                  {previewText}
                </div>
              )}
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setPreviewItem(null)}>閉じる</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
