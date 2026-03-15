import { useState, useEffect, useCallback, useRef } from 'react';
import { createText, updateText, aiCorrect, aiGenerate, aiAlignDatetime, aiAgent } from '../api.js';

const LS_DATE = 'event_gen_date';
const LS_TIME = 'event_gen_time';
const LS_END_TIME = 'event_gen_end_time';
const LS_API_KEY = 'openai_api_key';

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

  // Datetime for AI generation (persisted in localStorage)
  const [genDate, setGenDate] = useState(() => localStorage.getItem(LS_DATE) || '');
  const [genTime, setGenTime] = useState(() => localStorage.getItem(LS_TIME) || '10:00');
  const [genEndTime, setGenEndTime] = useState(() => localStorage.getItem(LS_END_TIME) || '12:00');
  const [apiKey, setApiKey] = useState(() => localStorage.getItem(LS_API_KEY) || '');

  // LME event sub-type for generation
  const [eventSubType, setEventSubType] = useState('');

  const contentRef = useRef(null);
  const folderOptions = buildFolderOptions(folders);

  // Persist datetime/api key
  useEffect(() => { localStorage.setItem(LS_DATE, genDate); }, [genDate]);
  useEffect(() => { localStorage.setItem(LS_TIME, genTime); }, [genTime]);
  useEffect(() => { localStorage.setItem(LS_END_TIME, genEndTime); }, [genEndTime]);
  useEffect(() => { localStorage.setItem(LS_API_KEY, apiKey); }, [apiKey]);

  const handleSave = useCallback(async () => {
    if (!name.trim()) { showToast('名前を入力してください', 'error'); return; }
    setSaving(true);
    try {
      if (isEdit) {
        await updateText(type, item.id, { name: name.trim(), content, folder });
        showToast('更新しました', 'success');
      } else {
        await createText(type, { name: name.trim(), content, folder });
        showToast('作成しました', 'success');
      }
      await onSaved();
      onClose();
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setSaving(false);
    }
  }, [isEdit, type, item, name, content, folder, onSaved, onClose, showToast]);

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
        eventSubType,
      });
      setContent(data.content || '');
      showToast('生成完了', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setAiLoading('');
    }
  }, [name, type, apiKey, genDate, genTime, genEndTime, eventSubType, showToast]);

  // AI Align datetime
  const handleAlignDatetime = useCallback(async () => {
    if (!content.trim()) { showToast('テキストを入力してください', 'error'); return; }
    if (!genDate) { showToast('開催日（文章生成用）を入力してください', 'error'); return; }
    setAiLoading('align');
    try {
      const data = await aiAlignDatetime({
        text: content,
        eventDate: genDate,
        eventTime: genTime,
        eventEndTime: genEndTime,
        apiKey,
      });
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

  // Close on overlay click
  function handleOverlayClick(e) {
    if (e.target === e.currentTarget) onClose();
  }

  // Close on Escape
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
          {/* Name */}
          <div className="form-group">
            <label className="form-label">
              名前 <span className="form-label-required">*</span>
            </label>
            <input
              className="form-input"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="テキスト名を入力"
            />
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
            {/* eventSubType for LME-style generation */}
            {type === 'event' && (
              <div className="form-group" style={{ marginTop: '10px' }}>
                <label className="form-label">生成スタイル（LME用）</label>
                <select
                  className="form-select"
                  value={eventSubType}
                  onChange={(e) => setEventSubType(e.target.value)}
                >
                  <option value="">汎用イベント告知</option>
                  <option value="taiken">体験会（セミナー）形式</option>
                  <option value="study">受講生勉強会形式</option>
                </select>
              </div>
            )}
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
              className="ai-btn ai-btn-generate"
              onClick={handleGenerate}
              disabled={anyAiLoading}
            >
              {aiLoading === 'generate' ? <span className="spinner" /> : '✨'} タイトルから生成
            </button>
            <button
              className="ai-btn ai-btn-align"
              onClick={handleAlignDatetime}
              disabled={anyAiLoading}
            >
              {aiLoading === 'align' ? <span className="spinner" /> : '📅'} 日時を合わせる
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
