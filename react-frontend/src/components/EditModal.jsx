import { useState, useEffect, useCallback, useRef } from 'react';
import { createText, updateText, aiCorrect, aiGenerate, aiAlignDatetime, aiAgent, fetchZoomSettings, saveZoomSetting, deleteZoomSetting } from '../api.js';

const LS_DATE       = 'event_gen_date';
const LS_TIME       = 'event_gen_time';
const LS_END_TIME   = 'event_gen_end_time';
const LS_API_KEY    = 'openai_api_key';
const LS_LME_CHECKED  = 'lme_gen_checked';
const LS_LME_SUBTYPE  = 'lme_gen_subtype';
const LS_LME_SEND_DATE = 'lme_send_date';
const LS_LME_SEND_TIME = 'lme_send_time';
const LS_ZOOM_URL   = 'lme_zoom_url';
const LS_MEETING_ID = 'lme_meeting_id';
const LS_PASSCODE   = 'lme_passcode';

function buildFolderOptions(folders) {
  const opts = [{ value: '', label: '未分類' }];
  folders.forEach((parent) => {
    opts.push({ value: parent.name, label: parent.name });
    (parent.children || []).forEach((child) => {
      opts.push({ value: `${parent.name}/${child}`, label: `  ${parent.name} / ${child}` });
    });
  });
  return opts;
}

export default function EditModal({ item, type, folders, onClose, onSaved, showToast }) {
  const isEdit = !!item?.id;

  const [name, setName] = useState(item?.name || '');
  const [folder, setFolder] = useState(item?.folder || '');
  const [content, setContent] = useState(item?.content || '');
  const [saving, setSaving] = useState(false);

  // AI states
  const [aiLoading, setAiLoading] = useState('');
  const [agentPrompt, setAgentPrompt] = useState('');
  const [showAgent, setShowAgent] = useState(false);

  // Datetime for AI generation
  const [genDate, setGenDate] = useState(() => localStorage.getItem(LS_DATE) || '');
  const [genTime, setGenTime] = useState(() => localStorage.getItem(LS_TIME) || '10:00');
  const [genEndTime, setGenEndTime] = useState(() => localStorage.getItem(LS_END_TIME) || '12:00');
  const [apiKey, setApiKey] = useState(() => localStorage.getItem(LS_API_KEY) || '');

  // LME
  const [lmeChecked, setLmeChecked] = useState(() => localStorage.getItem(LS_LME_CHECKED) === 'true');
  const [eventSubType, setEventSubType] = useState(() => localStorage.getItem(LS_LME_SUBTYPE) || 'benkyokai');
  const [lmeSendDate, setLmeSendDate] = useState(() => localStorage.getItem(LS_LME_SEND_DATE) || '');
  const [lmeSendTime, setLmeSendTime] = useState(() => localStorage.getItem(LS_LME_SEND_TIME) || '10:00');
  const [zoomUrl, setZoomUrl] = useState(() => localStorage.getItem(LS_ZOOM_URL) || '');
  const [meetingId, setMeetingId] = useState(() => localStorage.getItem(LS_MEETING_ID) || '');
  const [passcode, setPasscode] = useState(() => localStorage.getItem(LS_PASSCODE) || '');

  // Zoom DB settings
  const [zoomList, setZoomList] = useState([]);
  const [zoomDropdownOpen, setZoomDropdownOpen] = useState(false);
  const [zoomSaving, setZoomSaving] = useState(false);

  // Voice
  const [isRecording, setIsRecording] = useState(false);
  const recognitionRef = useRef(null);

  const contentRef = useRef(null);
  const folderOptions = buildFolderOptions(folders);

  // Load Zoom settings from DB on mount
  useEffect(() => {
    fetchZoomSettings().then(setZoomList).catch(() => {});
  }, []);

  function handleLoadZoom(setting) {
    setZoomUrl(setting.zoomUrl || '');
    setMeetingId(setting.meetingId || '');
    setPasscode(setting.passcode || '');
    setZoomDropdownOpen(false);
    showToast(`Zoom設定「${setting.label}」を読み込みました`, 'success');
  }

  async function handleSaveZoom() {
    if (!zoomUrl) { showToast('Zoom URLを入力してください', 'error'); return; }
    const label = prompt('保存名を入力してください（例: 定例ミーティング）');
    if (!label) return;
    setZoomSaving(true);
    try {
      await saveZoomSetting({ label, zoomUrl, meetingId, passcode });
      const list = await fetchZoomSettings();
      setZoomList(list);
      showToast('Zoom設定を保存しました', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setZoomSaving(false);
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

  // Persist all settings
  useEffect(() => { localStorage.setItem(LS_DATE, genDate); }, [genDate]);
  useEffect(() => { localStorage.setItem(LS_TIME, genTime); }, [genTime]);
  useEffect(() => { localStorage.setItem(LS_END_TIME, genEndTime); }, [genEndTime]);
  useEffect(() => { localStorage.setItem(LS_API_KEY, apiKey); }, [apiKey]);
  useEffect(() => { localStorage.setItem(LS_LME_CHECKED, lmeChecked); }, [lmeChecked]);
  useEffect(() => { localStorage.setItem(LS_LME_SUBTYPE, eventSubType); }, [eventSubType]);
  useEffect(() => { localStorage.setItem(LS_LME_SEND_DATE, lmeSendDate); }, [lmeSendDate]);
  useEffect(() => { localStorage.setItem(LS_LME_SEND_TIME, lmeSendTime); }, [lmeSendTime]);
  useEffect(() => { localStorage.setItem(LS_ZOOM_URL, zoomUrl); }, [zoomUrl]);
  useEffect(() => { localStorage.setItem(LS_MEETING_ID, meetingId); }, [meetingId]);
  useEffect(() => { localStorage.setItem(LS_PASSCODE, passcode); }, [passcode]);

  const handleSave = useCallback(async () => {
    if (!name.trim()) { showToast('名前を入力してください', 'error'); return; }
    setSaving(true);
    try {
      let finalContent = content;

      // イベントタイプかつ日付・APIキーがある場合、日時を自動調整
      if (type === 'event' && genDate && apiKey && finalContent.trim()) {
        try {
          const res = await aiAlignDatetime({ text: finalContent, eventDate: genDate, eventTime: genTime, eventEndTime: genEndTime, apiKey });
          if (res.content) finalContent = res.content;
        } catch (_) { /* 失敗しても保存続行 */ }
      }

      // Zoom URL等のプレースホルダーを置換
      if (zoomUrl)   finalContent = finalContent.replace(/参加URL：\s*（後ほど共有）/g,        `参加URL： ${zoomUrl}`);
      if (meetingId) finalContent = finalContent.replace(/ミーティング ID:\s*（後ほど共有）/g, `ミーティング ID: ${meetingId}`);
      if (passcode)  finalContent = finalContent.replace(/パスコード:\s*（後ほど共有）/g,      `パスコード: ${passcode}`);

      if (isEdit) {
        await updateText(type, item.id, { name: name.trim(), content: finalContent, folder });
        showToast('更新しました', 'success');
      } else {
        await createText(type, { name: name.trim(), content: finalContent, folder });
        showToast('作成しました', 'success');
      }
      await onSaved();
      onClose();
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setSaving(false);
    }
  }, [isEdit, type, item, name, content, folder, genDate, genTime, genEndTime, apiKey, zoomUrl, meetingId, passcode, onSaved, onClose, showToast]);

  // AI Correct
  const handleCorrect = useCallback(async () => {
    if (!content.trim()) { showToast('テキストを入力してください', 'error'); return; }
    setAiLoading('correct');
    try {
      const data = await aiCorrect({ text: content, apiKey });
      setContent(data.corrected || content);
      showToast('校正完了', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setAiLoading('');
    }
  }, [content, apiKey, showToast]);

  // AI Generate
  const handleGenerate = useCallback(async () => {
    if (!name.trim()) { showToast('名前（タイトル）を入力してください', 'error'); return; }
    if (!genDate) { showToast('開催日（文章生成用）を入力してください', 'error'); return; }
    setAiLoading('generate');
    try {
      const data = await aiGenerate({
        title: name.trim(),
        type,
        apiKey,
        eventDate: genDate,
        eventTime: genTime,
        eventEndTime: genEndTime,
        eventSubType: lmeChecked ? eventSubType : null,
        zoomUrl:   lmeChecked ? zoomUrl   : '',
        meetingId: lmeChecked ? meetingId : '',
        passcode:  lmeChecked ? passcode  : '',
      });
      setContent(data.content || '');
      showToast('生成完了', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setAiLoading('');
    }
  }, [name, type, apiKey, genDate, genTime, genEndTime, eventSubType, lmeChecked, zoomUrl, meetingId, passcode, showToast]);

  // AI Align datetime
  const handleAlignDatetime = useCallback(async () => {
    if (!content.trim()) { showToast('テキストを入力してください', 'error'); return; }
    if (!genDate) { showToast('開催日（文章生成用）を入力してください', 'error'); return; }
    setAiLoading('align');
    try {
      const data = await aiAlignDatetime({ text: content, eventDate: genDate, eventTime: genTime, eventEndTime: genEndTime, apiKey });
      setContent(data.content || content);
      showToast('日時調整完了', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setAiLoading('');
    }
  }, [content, apiKey, genDate, genTime, genEndTime, showToast]);

  // AI Agent
  const handleAgent = useCallback(async () => {
    if (!agentPrompt.trim()) { showToast('指示を入力してください', 'error'); return; }
    setAiLoading('agent');
    try {
      const data = await aiAgent({ text: content, prompt: agentPrompt, apiKey });
      setContent(data.result || content);
      showToast('AIエージェント処理完了', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setAiLoading('');
    }
  }, [content, agentPrompt, apiKey, showToast]);

  // Voice input
  const handleVoice = useCallback(() => {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      showToast('お使いのブラウザは音声入力に対応していません（Chromeを使用してください）', 'error');
      return;
    }
    if (isRecording) {
      recognitionRef.current?.stop();
      setIsRecording(false);
      return;
    }
    const rec = new SpeechRecognition();
    rec.lang = 'ja-JP';
    rec.continuous = true;
    rec.interimResults = true;
    rec.onresult = (e) => {
      for (let i = e.resultIndex; i < e.results.length; i++) {
        if (e.results[i].isFinal) setContent((prev) => prev + e.results[i][0].transcript);
      }
    };
    rec.onend = () => setIsRecording(false);
    rec.start();
    recognitionRef.current = rec;
    setIsRecording(true);
  }, [isRecording, showToast]);

  function handleOverlayClick(e) {
    if (e.target === e.currentTarget) onClose();
  }

  useEffect(() => {
    function handleKeyDown(e) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  const anyAiLoading = !!aiLoading;

  return (
    <div className="modal-overlay" onClick={handleOverlayClick}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">{isEdit ? 'テキストを編集' : '新規テキスト作成'}</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div className="modal-body">
          {/* Name + Generate button */}
          <div className="form-group">
            <label className="form-label">
              名前 <span className="form-label-required">*</span>
            </label>
            <div className="name-generate-row">
              <input
                className="form-input"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="テキスト名を入力"
              />
              <button
                className="ai-btn ai-btn-generate"
                onClick={handleGenerate}
                disabled={anyAiLoading}
                title="タイトルに沿って文章を自動生成"
              >
                {aiLoading === 'generate' ? <span className="spinner" /> : '✨'} 文章自動生成
              </button>
            </div>
          </div>

          {/* Folder */}
          <div className="form-group">
            <label className="form-label">フォルダ</label>
            <select
              className="form-select"
              value={folder}
              onChange={(e) => setFolder(e.target.value)}
            >
              {folderOptions.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          {/* Datetime section for AI */}
          <div className="datetime-section">
            <p className="datetime-section-label">AI文章生成用の日時設定</p>
            <div className="form-row-3">
              <div className="form-group">
                <label className="form-label">開催日</label>
                <input
                  className="form-input"
                  type="date"
                  value={genDate}
                  onChange={(e) => setGenDate(e.target.value)}
                />
              </div>
              <div className="form-group">
                <label className="form-label">開始時刻</label>
                <input
                  className="form-input"
                  type="time"
                  value={genTime}
                  onChange={(e) => setGenTime(e.target.value)}
                />
              </div>
              <div className="form-group">
                <label className="form-label">終了時刻</label>
                <input
                  className="form-input"
                  type="time"
                  value={genEndTime}
                  onChange={(e) => setGenEndTime(e.target.value)}
                />
              </div>
            </div>

            {/* LME settings - 一時コメントアウト（エルメ側で配信ユーザー絞り込み調整中） */}
            {/* {type === 'event' && (
              <div className="lme-gen-section">
                <label className="lme-gen-check">
                  <input
                    type="checkbox"
                    checked={lmeChecked}
                    onChange={(e) => setLmeChecked(e.target.checked)}
                  />
                  <span>LME（LINE配信）向けに生成</span>
                </label>

                {lmeChecked && (
                  <div className="lme-gen-options">
                    <div className="lme-subtype-row">
                      {[
                        { value: 'benkyokai', label: '受講生勉強会' },
                        { value: 'taiken',    label: '体験会（セミナー）' },
                      ].map(({ value, label }) => (
                        <label key={value} className="lme-subtype-opt">
                          <input
                            type="radio"
                            name="edit-lme-subtype"
                            value={value}
                            checked={eventSubType === value}
                            onChange={() => setEventSubType(value)}
                          />
                          <span>{label}</span>
                        </label>
                      ))}
                    </div>

                    <div className="lme-senddate-row">
                      <span className="lme-senddate-label">配信日時</span>
                      <input
                        className="form-input"
                        type="date"
                        value={lmeSendDate}
                        onChange={(e) => setLmeSendDate(e.target.value)}
                      />
                      <input
                        className="form-input"
                        type="time"
                        value={lmeSendTime}
                        onChange={(e) => setLmeSendTime(e.target.value)}
                      />
                    </div>

                    <div className="lme-zoom-fields">
                      <div className="lme-zoom-row">
                        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
                          <span className="lme-senddate-label">Zoom URL</span>
                          <div style={{ display: 'flex', gap: '6px', position: 'relative' }}>
                            <button
                              type="button"
                              className="btn btn-sm zoom-load-btn"
                              onClick={() => setZoomDropdownOpen(!zoomDropdownOpen)}
                              title="保存済みZoom設定を読み込む"
                            >
                              📥 読み込み
                            </button>
                            <button
                              type="button"
                              className="btn btn-sm zoom-save-btn"
                              onClick={handleSaveZoom}
                              disabled={zoomSaving || !zoomUrl}
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
                                        <span className="zoom-dropdown-label">{z.label}</span>
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
                        <input
                          className="form-input zoom-url-input"
                          type="url"
                          value={zoomUrl}
                          onChange={(e) => setZoomUrl(e.target.value)}
                          placeholder="https://zoom.us/j/..."
                        />
                      </div>
                      <div className="lme-zoom-row">
                        <span className="lme-senddate-label">ミーティング ID</span>
                        <input
                          className="form-input"
                          value={meetingId}
                          onChange={(e) => setMeetingId(e.target.value)}
                          placeholder="123 456 7890"
                        />
                      </div>
                      <div className="lme-zoom-row">
                        <span className="lme-senddate-label">パスコード</span>
                        <input
                          className="form-input"
                          value={passcode}
                          onChange={(e) => setPasscode(e.target.value)}
                          placeholder="abc123"
                        />
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )} */}

            {/* API Key */}
            <div className="form-group" style={{ marginTop: '10px' }}>
              <label className="form-label">OpenAI APIキー</label>
              <input
                className="form-input"
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder="sk-..."
              />
            </div>
          </div>

          {/* AI Buttons */}
          <div className="ai-buttons">
            <button
              className="ai-btn ai-btn-correct"
              onClick={handleCorrect}
              disabled={anyAiLoading}
            >
              {aiLoading === 'correct' ? <span className="spinner" /> : '✅'} 文章校正
            </button>
            <button
              className="ai-btn ai-btn-align"
              onClick={handleAlignDatetime}
              disabled={anyAiLoading}
            >
              {aiLoading === 'align' ? <span className="spinner" /> : '📅'} 日時を合わせる
            </button>
            <button
              className={`ai-btn ai-btn-voice${isRecording ? ' recording' : ''}`}
              onClick={handleVoice}
              title="音声入力"
            >
              🎤 {isRecording ? '録音中...' : '音声入力'}
            </button>
            <button
              className="ai-btn ai-btn-agent"
              onClick={() => setShowAgent(!showAgent)}
              disabled={anyAiLoading && aiLoading !== 'agent'}
            >
              {aiLoading === 'agent' ? <span className="spinner" /> : '🤖'} AIエージェント
            </button>
          </div>

          {showAgent && (
            <div className="agent-input-row">
              <input
                className="agent-input"
                placeholder="AIへの指示を入力（例：もっと短くしてください）"
                value={agentPrompt}
                onChange={(e) => setAgentPrompt(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') handleAgent(); }}
              />
              <button
                className="ai-btn ai-btn-agent"
                onClick={handleAgent}
                disabled={anyAiLoading}
              >
                実行
              </button>
            </div>
          )}

          {/* Content */}
          <div className="form-group">
            <label className="form-label">内容</label>
            <textarea
              ref={contentRef}
              className="form-textarea tall"
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder="テキスト内容を入力してください"
            />
          </div>
        </div>

        <div className="modal-footer">
          <button className="btn btn-secondary" onClick={onClose}>キャンセル</button>
          <button
            className="btn btn-primary"
            onClick={handleSave}
            disabled={saving}
          >
            {saving ? <><span className="spinner" /> 保存中...</> : isEdit ? '更新する' : '作成する'}
          </button>
        </div>
      </div>
    </div>
  );
}
