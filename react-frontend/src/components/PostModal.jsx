import { useState, useEffect, useRef, useCallback } from 'react';
import { postToSites, fetchZoomSettings, saveZoomSetting, deleteZoomSetting, createZoomMeeting } from '../api.js';

const LS_API_KEY       = 'openai_api_key';
const LS_DATE          = 'event_gen_date';
const LS_TIME          = 'event_gen_time';
const LS_END_TIME      = 'event_gen_end_time';
const LS_LME_SEND_DATE = 'lme_send_date';
const LS_LME_SEND_TIME = 'lme_send_time';
// EditModal と共有する Zoom 関連キー
const LS_ZOOM_URL      = 'lme_zoom_url';
const LS_MEETING_ID    = 'lme_meeting_id';
const LS_PASSCODE      = 'lme_passcode';

// LME 一時非表示（エルメ側で配信ユーザー絞り込み調整中）
const SITES = ['こくチーズ', 'Peatix', 'connpass', 'TechPlay' /*, 'LME' */];

function getDefaultEventFields() {
  return {
    title:        '',
    startDate:    localStorage.getItem(LS_DATE)         || '',
    startTime:    localStorage.getItem(LS_TIME)         || '10:00',
    endDate:      localStorage.getItem(LS_DATE)         || '',
    endTime:      localStorage.getItem(LS_END_TIME)     || '12:00',
    place:        'オンライン',
    zoomTitle:    '',
    zoomUrl:      localStorage.getItem(LS_ZOOM_URL)   || '',
    zoomId:       localStorage.getItem(LS_MEETING_ID) || '',
    zoomPasscode: (() => { const v = localStorage.getItem(LS_PASSCODE) || ''; return /\*/.test(v) ? '' : v; })(),
    capacity:     '50',
    tel:          '03-1234-5678',
    peatixEventId: '',
    lmeSendDate:  localStorage.getItem(LS_LME_SEND_DATE) || '',
    lmeSendTime:  localStorage.getItem(LS_LME_SEND_TIME) || localStorage.getItem(LS_TIME) || '10:00',
  };
}

export default function PostModal({ item, onClose, showToast }) {
  const [selectedSites, setSelectedSites] = useState(() => {
    try {
      const saved = localStorage.getItem('post_selected_sites');
      const sites = saved ? JSON.parse(saved) : ['こくチーズ'];
      const lmeChecked = localStorage.getItem('lme_gen_checked') === 'true';
      if (lmeChecked && !sites.includes('LME')) sites.push('LME');
      return sites;
    } catch {
      return ['こくチーズ'];
    }
  });
  const [lmeSubType, setLmeSubType] = useState(
    () => localStorage.getItem('lme_gen_subtype') || 'taiken'
  );
  const [eventFields, setEventFields] = useState(getDefaultEventFields);
  const [generateImage, setGenerateImage] = useState(false);
  const [imageStyle, setImageStyle] = useState('cute');
  const [apiKey, setApiKey] = useState(() => localStorage.getItem(LS_API_KEY) || '');

  // 公開/非公開設定（デフォルト: 非公開）
  const [publishSites, setPublishSites] = useState({});

  const [posting, setPosting] = useState(false);
  const [logs, setLogs] = useState([]);
  const [siteStatuses, setSiteStatuses] = useState({});
  const [postDone, setPostDone] = useState(false);

  // Zoom DB settings
  const [zoomList, setZoomList] = useState([]);
  const [zoomDropdownOpen, setZoomDropdownOpen] = useState(false);
  const [zoomSaving, setZoomSaving] = useState(false);
  const [zoomCreating, setZoomCreating] = useState(false);
  const [showPasscode, setShowPasscode] = useState(true);
  const [zoomLogs, setZoomLogs] = useState([]);

  const logRef = useRef(null);

  // Load Zoom settings from DB on mount
  useEffect(() => {
    fetchZoomSettings().then(setZoomList).catch(() => {});
  }, []);

  function handleLoadZoom(setting) {
    setEventFields((prev) => ({
      ...prev,
      zoomTitle: setting.title || setting.label || '',
      zoomUrl: setting.zoomUrl,
      zoomId: setting.meetingId || '',
      zoomPasscode: (setting.passcode && !/\*/.test(setting.passcode)) ? setting.passcode : '',
    }));
    setZoomDropdownOpen(false);
    showToast(`Zoom設定「${setting.label}」を読み込みました`, 'success');
  }

  async function handleSaveZoom() {
    if (!eventFields.zoomUrl) {
      showToast('Zoom URLを入力してください', 'error');
      return;
    }
    const label = prompt('保存名を入力してください（例: 定例ミーティング）');
    if (!label) return;
    setZoomSaving(true);
    try {
      await saveZoomSetting({
        label,
        title: eventFields.zoomTitle || eventFields.title || '',
        zoomUrl: eventFields.zoomUrl,
        meetingId: eventFields.zoomId,
        passcode: eventFields.zoomPasscode,
      });
      const list = await fetchZoomSettings();
      setZoomList(list);
      showToast('Zoom設定を保存しました', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setZoomSaving(false);
    }
  }

  async function handleCreateZoomMeeting() {
    if (!eventFields.title && !item?.name) {
      showToast('イベント名を入力してください', 'error');
      return;
    }
    if (!eventFields.startDate) {
      showToast('開催日を入力してください', 'error');
      return;
    }
    setZoomCreating(true);
    setZoomLogs([]);
    try {
      let zoomResult = null;
      await createZoomMeeting(
        {
          title: eventFields.zoomTitle || eventFields.title || item?.name || 'ミーティング',
          startDate: eventFields.startDate,
          startTime: eventFields.startTime || '10:00',
          duration: 120,
        },
        (event) => {
          if (event.type === 'log') {
            setZoomLogs((prev) => [...prev, event.message]);
          } else if (event.type === 'error') {
            setZoomLogs((prev) => [...prev, `❌ ${event.message}`]);
            showToast(event.message, 'error');
          } else if (event.type === 'result' && event.data) {
            zoomResult = event.data;
            setEventFields((prev) => ({
              ...prev,
              zoomTitle: event.data.title || event.data.label || '',
              zoomUrl: event.data.zoomUrl || '',
              zoomId: event.data.meetingId || '',
              zoomPasscode: (event.data.passcode && !/\*/.test(event.data.passcode)) ? event.data.passcode : '',
            }));
            showToast('Zoomミーティングを作成・DB保存し、自動入力しました', 'success');
          }
        }
      );
      // Refresh zoom list
      const list = await fetchZoomSettings();
      setZoomList(list);
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setZoomCreating(false);
    }
  }

  async function handleDeleteZoom(id, label) {
    if (!confirm(`Zoom設定「${label}」を削除しますか？`)) return;
    try {
      await deleteZoomSetting(id);
      const list = await fetchZoomSettings();
      setZoomList(list);
      showToast('Zoom設定を削除しました', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  // Auto-fill title and zoomTitle from item name
  useEffect(() => {
    if (item) {
      setEventFields((prev) => ({
        ...prev,
        title: prev.title || item.name,
        zoomTitle: prev.zoomTitle || item.name,
      }));
    }
  }, [item]);

  // Persist api key
  useEffect(() => { localStorage.setItem(LS_API_KEY, apiKey); }, [apiKey]);

  // Persist selected sites
  useEffect(() => {
    localStorage.setItem('post_selected_sites', JSON.stringify(selectedSites));
  }, [selectedSites]);

  // Auto scroll logs
  useEffect(() => {
    if (logRef.current) {
      logRef.current.scrollTop = logRef.current.scrollHeight;
    }
  }, [logs]);

  // Persist LME send date/time
  useEffect(() => { localStorage.setItem(LS_LME_SEND_DATE, eventFields.lmeSendDate); }, [eventFields.lmeSendDate]);
  useEffect(() => { localStorage.setItem(LS_LME_SEND_TIME, eventFields.lmeSendTime); }, [eventFields.lmeSendTime]);

  // Persist Zoom fields (EditModal と共有)
  useEffect(() => { localStorage.setItem(LS_ZOOM_URL,   eventFields.zoomUrl);      }, [eventFields.zoomUrl]);
  useEffect(() => { localStorage.setItem(LS_MEETING_ID, eventFields.zoomId);       }, [eventFields.zoomId]);
  useEffect(() => { localStorage.setItem(LS_PASSCODE,   eventFields.zoomPasscode); }, [eventFields.zoomPasscode]);

  // 開始日を変更したら終了日・Zoomタイトルの日付も連動
  function handleStartDateChange(val) {
    setEventFields((prev) => {
      const updated = { ...prev, startDate: val, endDate: val };
      // Zoomタイトルの日付プレフィックスを更新
      if (val && updated.zoomTitle) {
        const d = new Date(val);
        const prefix = `${d.getMonth() + 1}/${d.getDate()} `;
        // 既存の日付プレフィックス（M/D ）を置換、なければ先頭に追加
        updated.zoomTitle = updated.zoomTitle.replace(/^\d{1,2}\/\d{1,2}\s+/, '');
        updated.zoomTitle = prefix + updated.zoomTitle;
      }
      return updated;
    });
  }

  function toggleSite(site) {
    setSelectedSites((prev) =>
      prev.includes(site) ? prev.filter((s) => s !== site) : [...prev, site]
    );
  }

  function updateEventField(key, value) {
    setEventFields((prev) => ({ ...prev, [key]: value }));
  }

  const handlePost = useCallback(async () => {
    if (selectedSites.length === 0) {
      showToast('投稿先サイトを選択してください', 'error');
      return;
    }

    setPosting(true);
    setLogs([]);
    setSiteStatuses({});
    setPostDone(false);

    const effectiveSites = selectedSites.map((s) => s === 'LME' ? `LME:${lmeSubType}` : s);
    const ef = {
      ...eventFields,
      lmeAccount: lmeSubType,
      publishSites: publishSites,
    };

    // 投稿内容にZoom情報を自動反映
    let finalContent = item.content;
    const { zoomUrl, zoomId, zoomPasscode } = eventFields;
    if (zoomUrl) {
      // プレースホルダーがあれば置換
      finalContent = finalContent.replace(/参加URL[：:]\s*（後ほど共有）/g, `参加URL： ${zoomUrl}`);
      finalContent = finalContent.replace(/ミーティング\s*ID[：:]\s*（後ほど共有）/g, `ミーティング ID: ${zoomId || ''}`);
      finalContent = finalContent.replace(/パスコード[：:]\s*（後ほど共有）/g, `パスコード: ${zoomPasscode || ''}`);

      // Zoom情報が本文に含まれていなければ末尾に追加
      if (!finalContent.includes(zoomUrl)) {
        const zoomBlock = [
          '\n\n■ Zoom参加情報',
          `参加URL: ${zoomUrl}`,
          zoomId ? `ミーティングID: ${zoomId}` : '',
          zoomPasscode ? `パスコード: ${zoomPasscode}` : '',
        ].filter(Boolean).join('\n');
        finalContent += zoomBlock;
      }
    }

    try {
      await postToSites(
        {
          content: finalContent,
          sites: effectiveSites,
          eventFields: ef,
          generateImage,
          imageStyle,
          openaiApiKey: apiKey,
        },
        (event) => {
          if (event.type === 'log') {
            setLogs((prev) => [...prev, { type: 'log', text: event.message }]);
          } else if (event.type === 'error') {
            setLogs((prev) => [...prev, { type: 'error', text: event.message }]);
          } else if (event.type === 'status') {
            const site = event.site;
            const status = event.status;
            setSiteStatuses((prev) => ({ ...prev, [site]: status }));
            const statusText = status === 'success' ? '✅ 成功' : status === 'error' ? '❌ 失敗' : '⏳ 実行中';
            setLogs((prev) => [...prev, { type: status === 'success' ? 'success' : status === 'error' ? 'error' : 'status', text: `[${site}] ${statusText}` }]);
          } else if (event.type === 'done') {
            setLogs((prev) => [...prev, { type: 'success', text: '===== 投稿完了 =====' }]);
            setPostDone(true);
          }
        }
      );
    } catch (err) {
      setLogs((prev) => [...prev, { type: 'error', text: `エラー: ${err.message}` }]);
      showToast(err.message, 'error');
    } finally {
      setPosting(false);
    }
  }, [selectedSites, lmeSubType, eventFields, generateImage, imageStyle, apiKey, item, showToast]);

  function handleOverlayClick(e) {
    if (e.target === e.currentTarget && !posting) onClose();
  }

  useEffect(() => {
    function handleKeyDown(e) {
      if (e.key === 'Escape' && !posting) onClose();
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose, posting]);

  function getSiteDisplayStatus(site) {
    if (siteStatuses[site]) return siteStatuses[site];
    if (site === 'LME') {
      return siteStatuses[`LME:${lmeSubType}`] || siteStatuses['LME'];
    }
    return null;
  }

  const lmeSelected = selectedSites.includes('LME');

  return (
    <div className="modal-overlay" onClick={handleOverlayClick}>
      <div className="modal post-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">投稿: {item?.name}</h2>
          <button className="modal-close" onClick={onClose} disabled={posting}>✕</button>
        </div>

        <div className="modal-body">
          {/* Site selection */}
          <div className="form-group">
            <label className="form-label">投稿先サイト</label>
            <div className="site-cards">
              {SITES.map((site) => {
                const isChecked = selectedSites.includes(site);
                const status = getSiteDisplayStatus(site);
                return (
                  <div key={site} className={`site-card ${isChecked ? 'checked' : ''}`}>
                    <div
                      className="site-card-header"
                      onClick={() => !posting && toggleSite(site)}
                    >
                      <button
                        type="button"
                        className={`publish-toggle ${publishSites[site] ? 'publish-on' : 'publish-off'}`}
                        onClick={(e) => {
                          e.stopPropagation();
                          if (!posting) setPublishSites((prev) => ({ ...prev, [site]: !prev[site] }));
                        }}
                        disabled={posting}
                        title={publishSites[site] ? '公開する' : '非公開'}
                      >
                        {publishSites[site] ? '公開' : '非公開'}
                      </button>
                      <input
                        type="checkbox"
                        className="site-checkbox"
                        checked={isChecked}
                        onChange={() => !posting && toggleSite(site)}
                        onClick={(e) => e.stopPropagation()}
                        disabled={posting}
                      />
                      <span className="site-name">{site}</span>
                      {status && (
                        <span className={`site-status ${status}`}>
                          {status === 'running' ? '実行中...' : status === 'success' ? '成功' : '失敗'}
                        </span>
                      )}
                      {posting && !status && isChecked && (
                        <span className="site-status running">待機中</span>
                      )}
                    </div>
                    {/* LME sub-options */}
                    {site === 'LME' && isChecked && (
                      <div className="lme-sub-options">
                        <div className="lme-account-row">
                          {[
                            { value: 'taiken',    label: '体験会（セミナー）' },
                            { value: 'benkyokai', label: '受講生勉強会' },
                          ].map(({ value, label }) => (
                            <label key={value} className="lme-radio">
                              <input
                                type="radio"
                                name="lme-subtype"
                                value={value}
                                checked={lmeSubType === value}
                                onChange={() => setLmeSubType(value)}
                                disabled={posting}
                              />
                              {label}
                            </label>
                          ))}
                        </div>
                        <div className="lme-senddate-row" style={{ marginTop: '8px' }}>
                          <span className="lme-senddate-label">配信日時</span>
                          <input
                            className="form-input"
                            type="date"
                            value={eventFields.lmeSendDate}
                            onChange={(e) => updateEventField('lmeSendDate', e.target.value)}
                            disabled={posting}
                          />
                          <input
                            className="form-input"
                            type="time"
                            value={eventFields.lmeSendTime}
                            onChange={(e) => updateEventField('lmeSendTime', e.target.value)}
                            disabled={posting}
                          />
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          {/* Event Fields */}
          <details className="event-fields-section" open>
            <summary className="event-fields-title">
              📅 イベント詳細 <span style={{ fontSize: '0.8em', color: '#888' }}>（こくチーズ用・受付期間は開催7日前〜1日前で自動計算）</span>
            </summary>

            <div className="form-group" style={{ marginTop: '10px' }}>
              <label className="form-label">イベント名（こくチーズ・connpassのタイトル）</label>
              <input
                className="form-input"
                value={eventFields.title}
                onChange={(e) => updateEventField('title', e.target.value)}
                placeholder="イベントタイトル"
                disabled={posting}
              />
            </div>

            <div className="form-row" style={{ marginTop: '10px' }}>
              <div className="form-group">
                <label className="form-label">開催日</label>
                <input
                  className="form-input"
                  type="date"
                  value={eventFields.startDate}
                  onChange={(e) => handleStartDateChange(e.target.value)}
                  disabled={posting}
                />
              </div>
              <div className="form-group">
                <label className="form-label">開始時刻</label>
                <input
                  className="form-input"
                  type="time"
                  value={eventFields.startTime}
                  onChange={(e) => updateEventField('startTime', e.target.value)}
                  disabled={posting}
                />
              </div>
            </div>

            <div className="form-row" style={{ marginTop: '10px' }}>
              <div className="form-group">
                <label className="form-label">終了日</label>
                <input
                  className="form-input"
                  type="date"
                  value={eventFields.endDate}
                  onChange={(e) => updateEventField('endDate', e.target.value)}
                  disabled={posting}
                />
              </div>
              <div className="form-group">
                <label className="form-label">終了時刻</label>
                <input
                  className="form-input"
                  type="time"
                  value={eventFields.endTime}
                  onChange={(e) => updateEventField('endTime', e.target.value)}
                  disabled={posting}
                />
              </div>
            </div>

            <div className="form-row" style={{ marginTop: '10px' }}>
              <div className="form-group">
                <label className="form-label">会場名</label>
                <input
                  className="form-input"
                  value={eventFields.place}
                  onChange={(e) => updateEventField('place', e.target.value)}
                  placeholder="例: オンライン"
                  disabled={posting}
                />
              </div>
              <div className="form-group">
                <label className="form-label">定員</label>
                <input
                  className="form-input"
                  type="number"
                  value={eventFields.capacity}
                  onChange={(e) => updateEventField('capacity', e.target.value)}
                  min="1"
                  disabled={posting}
                />
              </div>
            </div>

            {/* Zoom Section */}
            <div className="zoom-section" style={{ marginTop: '10px', background: '#f0f7ff', border: '1.5px solid #bfdbfe', borderRadius: '10px', padding: '14px' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '10px', flexWrap: 'wrap', gap: '6px' }}>
                <label className="form-label" style={{ margin: 0, fontSize: '13px', fontWeight: 700, color: '#1e40af' }}>
                  Zoom ミーティング
                </label>
                <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', position: 'relative' }}>
                  <button
                    type="button"
                    className="btn btn-sm zoom-create-btn"
                    onClick={handleCreateZoomMeeting}
                    disabled={posting || zoomCreating}
                    title="Zoomにログインしてミーティングを自動作成"
                  >
                    {zoomCreating ? <><span className="spinner" /> 作成中...</> : '🔄 自動作成'}
                  </button>
                  <button
                    type="button"
                    className="btn btn-sm zoom-load-btn"
                    onClick={() => setZoomDropdownOpen(!zoomDropdownOpen)}
                    disabled={posting || zoomCreating}
                    title="保存済みZoom設定を読み込む"
                  >
                    📥 読み込み
                  </button>
                  <button
                    type="button"
                    className="btn btn-sm zoom-save-btn"
                    onClick={handleSaveZoom}
                    disabled={posting || zoomSaving || zoomCreating || !eventFields.zoomUrl}
                    title="現在のZoom設定をDBに保存"
                  >
                    {zoomSaving ? <span className="spinner" /> : '💾'} 保存
                  </button>
                  {zoomDropdownOpen && (
                    <div className="zoom-dropdown">
                      {zoomList.length === 0 ? (
                        <div className="zoom-dropdown-empty">保存済み設定なし</div>
                      ) : (
                        zoomList.map((z) => (
                          <div key={z.id} className="zoom-dropdown-item">
                            <button
                              className="zoom-dropdown-select"
                              onClick={() => handleLoadZoom(z)}
                            >
                              <span className="zoom-dropdown-label">{z.title || z.label}</span>
                              <span className="zoom-dropdown-url">{z.zoomUrl?.substring(0, 40)}...</span>
                            </button>
                            <button
                              className="zoom-dropdown-delete"
                              onClick={(e) => { e.stopPropagation(); handleDeleteZoom(z.id, z.label); }}
                              title="削除"
                            >
                              ✕
                            </button>
                          </div>
                        ))
                      )}
                    </div>
                  )}
                </div>
              </div>

              {/* Zoom auto-create logs */}
              {zoomLogs.length > 0 && (
                <div className="zoom-log-container" style={{ marginBottom: '10px' }}>
                  {zoomLogs.map((msg, i) => (
                    <div key={i} className="zoom-log-line">{msg}</div>
                  ))}
                </div>
              )}

              <div className="form-group">
                <label className="form-label">Zoom タイトル</label>
                <input
                  className="form-input"
                  value={eventFields.zoomTitle}
                  onChange={(e) => updateEventField('zoomTitle', e.target.value)}
                  placeholder="例: 3/29 テスト体験会"
                  disabled={posting || zoomCreating}
                />
              </div>

              <div className="form-group" style={{ marginTop: '8px' }}>
                <label className="form-label">Zoom URL</label>
                <input
                  className="form-input zoom-url-input"
                  value={eventFields.zoomUrl}
                  onChange={(e) => updateEventField('zoomUrl', e.target.value)}
                  placeholder="https://us02web.zoom.us/j/..."
                  disabled={posting || zoomCreating}
                />
              </div>

              <div className="form-row" style={{ marginTop: '8px' }}>
                <div className="form-group">
                  <label className="form-label">ミーティングID</label>
                  <input
                    className="form-input"
                    value={eventFields.zoomId}
                    onChange={(e) => updateEventField('zoomId', e.target.value)}
                    placeholder="123 456 7890"
                    disabled={posting || zoomCreating}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">パスコード</label>
                  <div className="passcode-input-row">
                    <input
                      className="form-input"
                      type={showPasscode ? 'text' : 'password'}
                      value={eventFields.zoomPasscode}
                      onChange={(e) => updateEventField('zoomPasscode', e.target.value)}
                      placeholder="数字6桁（例: 311071）"
                      disabled={posting || zoomCreating}
                    />
                    <button
                      type="button"
                      className="btn btn-sm passcode-toggle"
                      onClick={() => setShowPasscode(!showPasscode)}
                      title={showPasscode ? 'パスコードを隠す' : 'パスコードを表示'}
                    >
                      {showPasscode ? '🙈' : '👁️'}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div className="form-group" style={{ marginTop: '10px' }}>
              <label className="form-label">連絡先TEL</label>
              <input
                className="form-input"
                value={eventFields.tel}
                onChange={(e) => updateEventField('tel', e.target.value)}
                placeholder="03-xxxx-xxxx"
                disabled={posting}
              />
            </div>

            <div className="form-group" style={{ marginTop: '10px', paddingBottom: '14px' }}>
              <label className="form-label">Peatix イベントID <span style={{ color: '#888', fontSize: '0.85em' }}>（入力時は新規作成せず既存イベントを更新）</span></label>
              <input
                className="form-input"
                value={eventFields.peatixEventId}
                onChange={(e) => updateEventField('peatixEventId', e.target.value)}
                placeholder="例: 12345678"
                disabled={posting}
              />
            </div>
          </details>

          {/* Image generation */}
          <div className="image-gen-row">
            <label className="image-gen-toggle">
              <input
                type="checkbox"
                checked={generateImage}
                onChange={(e) => setGenerateImage(e.target.checked)}
                disabled={posting}
                style={{ accentColor: '#f472b6' }}
              />
              🖼️ 画像自動生成（DALL-E 3）
            </label>
            {generateImage && (
              <div className="image-style-radio">
                <label>
                  <input
                    type="radio"
                    name="image-style"
                    value="cute"
                    checked={imageStyle === 'cute'}
                    onChange={() => setImageStyle('cute')}
                    disabled={posting}
                  />
                  🌸 可愛い系
                </label>
                <label>
                  <input
                    type="radio"
                    name="image-style"
                    value="cool"
                    checked={imageStyle === 'cool'}
                    onChange={() => setImageStyle('cool')}
                    disabled={posting}
                  />
                  ⚡ かっこいい系
                </label>
              </div>
            )}
          </div>

          {/* API Key */}
          <div className="api-key-section">
            <p className="api-key-label">OpenAI APIキー（画像生成に使用）</p>
            <input
              className="api-key-input"
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="sk-..."
              disabled={posting}
            />
          </div>

          {/* 実行ログ */}
          {(posting || postDone || logs.length > 0) && (
            <div className="log-section">
              <p className="log-section-title">実行ログ</p>
              <div className="sse-log-container" ref={logRef}>
                {logs.length === 0 && posting && (
                  <div className="sse-log-line log">投稿処理を開始しています...</div>
                )}
                {logs.map((log, i) => (
                  <div key={i} className={`sse-log-line ${log.type}`}>
                    {log.text}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="modal-footer">
          <button
            className="btn btn-secondary"
            onClick={onClose}
            disabled={posting}
          >
            {postDone ? '閉じる' : 'キャンセル'}
          </button>
          {!postDone && (
            <button
              className="btn btn-primary"
              onClick={handlePost}
              disabled={posting || selectedSites.length === 0}
            >
              {posting
                ? <><span className="spinner" /> 投稿中...</>
                : '投稿する →'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
