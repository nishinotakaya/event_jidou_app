import { useState, useEffect, useRef, useCallback } from 'react';
import { postToSites } from '../api.js';

const LS_API_KEY = 'openai_api_key';

const SITES = ['こくチーズ', 'Peatix', 'connpass', 'LME'];

const DEFAULT_EVENT_FIELDS = {
  title: '',
  startDate: '',
  startTime: '',
  endDate: '',
  endTime: '',
  place: '',
  zoomUrl: '',
  capacity: '',
  tel: '',
  peatixEventId: '',
};

export default function PostModal({ item, onClose, showToast }) {
  const [selectedSites, setSelectedSites] = useState(() => {
    try {
      const saved = localStorage.getItem('post_selected_sites');
      return saved ? JSON.parse(saved) : ['こくチーズ'];
    } catch {
      return ['こくチーズ'];
    }
  });
  const [lmeSubType, setLmeSubType] = useState('taiken');
  const [eventFields, setEventFields] = useState(DEFAULT_EVENT_FIELDS);
  const [generateImage, setGenerateImage] = useState(false);
  const [imageStyle, setImageStyle] = useState('cute');
  const [apiKey, setApiKey] = useState(() => localStorage.getItem(LS_API_KEY) || '');

  const [posting, setPosting] = useState(false);
  const [logs, setLogs] = useState([]);
  const [siteStatuses, setSiteStatuses] = useState({});
  const [postDone, setPostDone] = useState(false);

  const logRef = useRef(null);

  // Auto-fill title from item name
  useEffect(() => {
    if (item) {
      setEventFields((prev) => ({
        ...prev,
        title: prev.title || item.name,
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

    // Build effective sites list (LME includes subType)
    const effectiveSites = selectedSites.map((s) => s === 'LME' ? `LME:${lmeSubType}` : s);

    // Effective event fields
    const ef = { ...eventFields };

    try {
      await postToSites(
        {
          content: item.content,
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

  // Compute display site name from effectiveSite key
  function getSiteDisplayStatus(site) {
    // Check both raw name and with LME subtype
    if (siteStatuses[site]) return siteStatuses[site];
    if (site === 'LME') {
      return siteStatuses[`LME:${lmeSubType}`] || siteStatuses['LME'];
    }
    return null;
  }

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
                        <label className="lme-radio">
                          <input
                            type="radio"
                            name="lme-subtype"
                            value="taiken"
                            checked={lmeSubType === 'taiken'}
                            onChange={() => setLmeSubType('taiken')}
                            disabled={posting}
                          />
                          体験会（セミナー）
                        </label>
                        <label className="lme-radio">
                          <input
                            type="radio"
                            name="lme-subtype"
                            value="study"
                            checked={lmeSubType === 'study'}
                            onChange={() => setLmeSubType('study')}
                            disabled={posting}
                          />
                          受講生勉強会
                        </label>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          {/* Event Fields */}
          <div className="event-fields-section">
            <p className="event-fields-title">イベント情報</p>

            <div className="form-group">
              <label className="form-label">タイトル</label>
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
                <label className="form-label">開始日</label>
                <input
                  className="form-input"
                  type="date"
                  value={eventFields.startDate}
                  onChange={(e) => updateEventField('startDate', e.target.value)}
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

            <div className="form-group" style={{ marginTop: '10px' }}>
              <label className="form-label">開催場所</label>
              <input
                className="form-input"
                value={eventFields.place}
                onChange={(e) => updateEventField('place', e.target.value)}
                placeholder="例: オンライン（Zoom）"
                disabled={posting}
              />
            </div>

            <div className="form-group" style={{ marginTop: '10px' }}>
              <label className="form-label">Zoom URL</label>
              <input
                className="form-input"
                value={eventFields.zoomUrl}
                onChange={(e) => updateEventField('zoomUrl', e.target.value)}
                placeholder="https://us02web.zoom.us/..."
                disabled={posting}
              />
            </div>

            <div className="form-row" style={{ marginTop: '10px' }}>
              <div className="form-group">
                <label className="form-label">定員</label>
                <input
                  className="form-input"
                  type="number"
                  value={eventFields.capacity}
                  onChange={(e) => updateEventField('capacity', e.target.value)}
                  placeholder="50"
                  disabled={posting}
                />
              </div>
              <div className="form-group">
                <label className="form-label">電話番号</label>
                <input
                  className="form-input"
                  value={eventFields.tel}
                  onChange={(e) => updateEventField('tel', e.target.value)}
                  placeholder="03-xxxx-xxxx"
                  disabled={posting}
                />
              </div>
            </div>

            <div className="form-group" style={{ marginTop: '10px' }}>
              <label className="form-label">Peatix イベントID（既存イベントに投稿する場合）</label>
              <input
                className="form-input"
                value={eventFields.peatixEventId}
                onChange={(e) => updateEventField('peatixEventId', e.target.value)}
                placeholder="例: 1234567"
                disabled={posting}
              />
            </div>
          </div>

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
              画像を自動生成する
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
                  かわいい
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
                  かっこいい
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

          {/* SSE Logs */}
          {logs.length > 0 && (
            <div className="sse-log-container" ref={logRef}>
              {logs.map((log, i) => (
                <div key={i} className={`sse-log-line ${log.type}`}>
                  {log.text}
                </div>
              ))}
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
                : '投稿する'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
