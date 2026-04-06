import { useState, useEffect, useRef, useCallback } from 'react';
import { postToSites, fetchZoomSettings, saveZoomSetting, deleteZoomSetting, createZoomMeeting, fetchAppSettings, saveAppSettings, fetchServiceConnections, fetchPostingHistory, createText, updateText, aiGenerate, aiCorrect, aiAlignDatetime, aiAgent, fetchOnclassStudents, uploadOnclassImage, createCalendarEvent, uploadImage, checkDuplicateEvent } from '../api.js';

// 全サイトリスト
const ALL_SITES = [
  'こくチーズ', 'Peatix', 'connpass', 'TechPlay', 'つなゲート', 'Doorkeeper',
  'ストアカ', 'EventRegist', 'Luma', 'セミナーBiZ', 'ジモティー', 'Gmail', 'X', 'Instagram',
  /* 'PassMarket' — サービス終了 */
  /* 'セミナーズ' — セミナー作成ページへの遷移がブロックされるため一時停止 */
];

// 受講生サポート用サイト
const STUDENT_SITES = ['オンクラス'];

// オンクラス コミュニティチャンネル一覧
const ONCLASS_CHANNELS = [
  '全体チャンネル',
  'もくもく会',
  '人工インターン - チーム【フリーエンジニア養成コース】',
  '勤怠A - 報告',
  '勤怠B - 報告',
  '勤怠a-ポートチーム5【フリーエンジニア養成コース】',
  'PDCAアプリ開発',
  'TodoB - 質問',
  'TodoB - 報告',
  'TodoA - 質問',
  'TodoA - 報告',
  'クローンチーム',
  'Aチーム（元基礎編）',
  'Bチーム（元Todo）',
  'TechPutチーム',
];

// サイト表示名 → DB service_name マッピング
const SITE_TO_SERVICE = {
  'こくチーズ': 'kokuchpro', 'Peatix': 'peatix', 'connpass': 'connpass',
  'TechPlay': 'techplay', 'つなゲート': 'tunagate', 'Doorkeeper': 'doorkeeper',
  'セミナーズ': 'seminars', 'ストアカ': 'street_academy', 'EventRegist': 'eventregist',
  'PassMarket': 'passmarket', 'Luma': 'luma', 'セミナーBiZ': 'seminar_biz',
  'ジモティー': 'jimoty',
  'Gmail': 'gmail',
  'X': 'twitter',
  'Instagram': 'instagram',
  'オンクラス': 'onclass',
};

// 下書き非対応サイト（チェック=公開投稿、未チェック=投稿しない）
const PUBLISH_ONLY_SITES = new Set(['ストアカ', 'Luma', 'LME', 'Gmail', 'X', 'Instagram', 'オンクラス']);

const DEFAULT_EVENT_FIELDS = {
  title:        '',
  startDate:    '',
  startTime:    '10:00',
  endDate:      '',
  endTime:      '12:00',
  place:        'オンライン',
  zoomTitle:    '',
  zoomUrl:      '',
  zoomId:       '',
  zoomPasscode: '',
  capacity:     '50',
  tel:          '03-1234-5678',
  peatixEventId: '',
  lmeSendDate:  '',
  lmeSendTime:  '10:00',
  gmailTo:      '',
};

export default function PostModal({ item, folders = [], activeType = 'event', onClose, onSaved, showToast }) {
  const isStudentMode = activeType === 'student';
  const isGitReview = item?.folder === 'Gitレビュー' || (isStudentMode && item?.name?.startsWith('📝 コードレビュー'));
  const isNew = !item?.id;
  const [activeTab, setActiveTab] = useState(isNew ? 'edit' : 'post'); // 'edit' | 'post'

  // 編集用state
  const [editName, setEditName] = useState(item?.name || '');
  const [editContent, setEditContent] = useState(item?.content || '');
  const [editFolder, setEditFolder] = useState(item?.folder || '');
  const [editSaving, setEditSaving] = useState(false);
  const [aiLoading, setAiLoading] = useState('');
  const [agentPrompt, setAgentPrompt] = useState('');
  const [showAgent, setShowAgent] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const recognitionRef = useRef(null);
  const contentTextareaRef = useRef(null);

  // カーソル位置にテキストを挿入するヘルパー
  const insertAtCursor = (text) => {
    const el = contentTextareaRef.current;
    if (!el) { setEditContent((prev) => prev + text); return; }
    const start = el.selectionStart ?? el.value.length;
    const end = el.selectionEnd ?? start;
    const before = editContent.substring(0, start);
    const after = editContent.substring(end);
    const newContent = before + text + after;
    setEditContent(newContent);
    // カーソルを挿入テキストの後ろに移動
    requestAnimationFrame(() => {
      el.selectionStart = el.selectionEnd = start + text.length;
      el.focus();
    });
  };

  // 投稿用state
  const [selectedSites, setSelectedSites] = useState(isStudentMode ? ['オンクラス'] : ['こくチーズ']);
  const [lmeSubType, setLmeSubType] = useState('taiken');
  const [eventFields, setEventFields] = useState({ ...DEFAULT_EVENT_FIELDS });
  const [generateImage, setGenerateImage] = useState(false);
  const [imageStyle, setImageStyle] = useState('cute');
  const [apiKey, setApiKey] = useState('');
  const [dalleApiKey, setDalleApiKey] = useState('');
  const [settingsLoaded, setSettingsLoaded] = useState(false);

  // 公開/非公開設定（デフォルト: 非公開）
  const [publishSites, setPublishSites] = useState({});

  // Googleカレンダー登録
  const [syncToGcal, setSyncToGcal] = useState(true);

  // オンクラス チャンネル選択
  const [onclassChannels, setOnclassChannels] = useState(item?.onclassChannels?.length > 0 ? item.onclassChannels : ['全体チャンネル']);
  const [channelDropdownOpen, setChannelDropdownOpen] = useState(false);

  // オンクラス メンション対象（フロントコース受講生）
  const [onclassStudents, setOnclassStudents] = useState([]);
  const [selectedMentions, setSelectedMentions] = useState([]);
  const [studentsLoading, setStudentsLoading] = useState(false);
  const [mentionDropdownOpen, setMentionDropdownOpen] = useState(false);

  // 受講生サポート種別（受講生告知 / イベント）
  const [studentPostType, setStudentPostType] = useState(item?.studentPostType || '受講生告知');

  // オンクラス初期読み込み完了フラグ（自動保存の誤発火防止）
  const onclassInitializedRef = useRef(false);

  // オンクラス 画像添付（1枚のみ）
  const [onclassImage, setOnclassImage] = useState(null); // { file, preview, serverPath }
  const imageInputRef = useRef(null);

  const [posting, setPosting] = useState(false);
  const [logs, setLogs] = useState([]);
  const [siteStatuses, setSiteStatuses] = useState({});
  const [postDone, setPostDone] = useState(false);

  // Zoom DB settings
  const [zoomList, setZoomList] = useState([]);
  const [zoomDropdownOpen, setZoomDropdownOpen] = useState(false);
  const [zoomSaving, setZoomSaving] = useState(false);
  const [zoomCreating, setZoomCreating] = useState(false);
  const [zoomAutoCreated, setZoomAutoCreated] = useState(false);
  const [zoomEditing, setZoomEditing] = useState(false);
  const [showPasscode, setShowPasscode] = useState(true);
  const [zoomLogs, setZoomLogs] = useState([]);

  // 接続済みサイトのみ表示
  const [connectedServices, setConnectedServices] = useState(new Set());
  const BASE_SITES = isStudentMode ? STUDENT_SITES : ALL_SITES;
  const SITES = BASE_SITES.filter(site => connectedServices.has(SITE_TO_SERVICE[site]));

  // 投稿履歴（サイトごとの最新）
  const [postingHistoryMap, setPostingHistoryMap] = useState({});

  const logRef = useRef(null);

  // 受講生サポートモード: フロントコース受講生を取得（DB保存済みなら即表示）
  function loadOnclassStudents(refresh = false) {
    setStudentsLoading(true);
    fetchOnclassStudents(refresh)
      .then((data) => {
        const names = data.students || [];
        setOnclassStudents(names);
        // DB保存済みメンションがあれば復元、なければ全員選択
        if (!refresh && item?.onclassMentions?.length > 0) {
          setSelectedMentions(item.onclassMentions.filter(n => names.includes(n)));
        } else {
          setSelectedMentions(names);
        }
        if (!refresh) onclassInitializedRef.current = true;
        if (refresh && names.length > 0) showToast(`受講生データを更新しました（${names.length}名）`, 'success');
      })
      .catch((e) => {
        if (refresh) showToast(`受講生データの取得に失敗: ${e.message}`, 'error');
      })
      .finally(() => setStudentsLoading(false));
  }

  useEffect(() => {
    if (isStudentMode && selectedSites.includes('オンクラス') && onclassStudents.length === 0 && !studentsLoading) {
      loadOnclassStudents(false);
    }
  }, [isStudentMode, selectedSites]);

  // Load all settings from DB on mount
  useEffect(() => {
    fetchServiceConnections().then((conns) => {
      const connected = new Set(conns.filter(c => c.status === 'connected').map(c => c.serviceName));
      setConnectedServices(connected);
    }).catch(() => {});
    // 投稿履歴取得
    if (item?.id) {
      fetchPostingHistory(item.id).then((history) => {
        const map = {};
        history.forEach((h) => { map[h.siteName] = h; });
        setPostingHistoryMap(map);
      }).catch(() => {});
    }
    fetchZoomSettings().then(setZoomList).catch(() => {});
    fetchAppSettings().then((s) => {
      setEventFields((prev) => ({
        ...prev,
        startDate:    item?.eventDate     || s.event_gen_date     || prev.startDate,
        startTime:    item?.eventTime     || s.event_gen_time     || prev.startTime,
        endDate:      item?.eventDate     || s.event_gen_date     || prev.endDate,
        endTime:      item?.eventEndTime  || s.event_gen_end_time || prev.endTime,
        zoomUrl:      s.lme_zoom_url       || prev.zoomUrl,
        zoomId:       s.lme_meeting_id     || prev.zoomId,
        zoomPasscode: (s.lme_passcode && !/\*/.test(s.lme_passcode)) ? s.lme_passcode : prev.zoomPasscode,
        lmeSendDate:  s.lme_send_date      || prev.lmeSendDate,
        lmeSendTime:  s.lme_send_time      || prev.lmeSendTime,
      }));
      setApiKey(s.openai_api_key || '');
      setDalleApiKey(s.dalle_api_key || '');
      if (s.post_selected_sites && !isStudentMode) {
        try { setSelectedSites(JSON.parse(s.post_selected_sites)); } catch {}
      }
      if (s.lme_gen_subtype) setLmeSubType(s.lme_gen_subtype);
      setSettingsLoaded(true);
    }).catch(() => setSettingsLoaded(true));
  }, []);

  function handleLoadZoom(setting) {
    setEventFields((prev) => ({
      ...prev,
      zoomTitle: setting.title || setting.label || '',
      zoomUrl: setting.zoomUrl,
      zoomId: setting.meetingId || '',
      zoomPasscode: (setting.passcode && !/\*/.test(setting.passcode)) ? setting.passcode : '',
    }));
    setZoomAutoCreated(!!setting.title);
    setZoomEditing(false);
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
            setZoomAutoCreated(true);
            setZoomEditing(false);
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

  // Persist settings to DB (debounced)
  const saveTimerRef = useRef(null);
  useEffect(() => {
    if (!settingsLoaded) return;
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => {
      saveAppSettings({
        event_gen_date:     eventFields.startDate,
        event_gen_time:     eventFields.startTime,
        event_gen_end_time: eventFields.endTime,
        openai_api_key:     apiKey,
        dalle_api_key:      dalleApiKey,
        lme_zoom_url:       eventFields.zoomUrl,
        lme_meeting_id:     eventFields.zoomId,
        lme_passcode:       eventFields.zoomPasscode,
        lme_send_date:      eventFields.lmeSendDate,
        lme_send_time:      eventFields.lmeSendTime,
        post_selected_sites: JSON.stringify(selectedSites),
        lme_gen_subtype:    lmeSubType,
      }).catch(() => {});
    }, 500);
    return () => clearTimeout(saveTimerRef.current);
  }, [settingsLoaded, eventFields.startDate, eventFields.startTime, eventFields.endTime, apiKey, dalleApiKey, eventFields.zoomUrl, eventFields.zoomId, eventFields.zoomPasscode, eventFields.lmeSendDate, eventFields.lmeSendTime, selectedSites, lmeSubType]);

  // Auto scroll logs
  useEffect(() => {
    if (logRef.current) {
      logRef.current.scrollTop = logRef.current.scrollHeight;
    }
  }, [logs]);

  // 音声入力
  const handleVoice = useCallback(() => {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) { showToast('お使いのブラウザは音声入力に対応していません', 'error'); return; }
    if (isRecording) { recognitionRef.current?.stop(); setIsRecording(false); return; }
    const rec = new SpeechRecognition();
    rec.lang = 'ja-JP'; rec.continuous = true; rec.interimResults = true;
    rec.onresult = (e) => { for (let i = e.resultIndex; i < e.results.length; i++) { if (e.results[i].isFinal) setEditContent((prev) => prev + e.results[i][0].transcript); } };
    rec.onend = () => setIsRecording(false);
    rec.start(); recognitionRef.current = rec; setIsRecording(true);
  }, [isRecording, showToast]);

  // AI操作後の自動保存（軽量版 - Zoom作成や日時調整はスキップ）
  const autoSave = useCallback(async (content) => {
    if (!editName.trim()) return;
    try {
      if (isNew) {
        await createText(activeType, { name: editName.trim(), content, folder: editFolder, eventDate: eventFields.startDate || '', eventTime: eventFields.startTime || '', eventEndTime: eventFields.endTime || '', ...(isStudentMode ? { onclassMentions: selectedMentions, onclassChannels, studentPostType } : {}) });
      } else {
        await updateText(activeType, item.id, { name: editName.trim(), content, folder: editFolder, eventDate: eventFields.startDate || '', eventTime: eventFields.startTime || '', eventEndTime: eventFields.endTime || '', ...(isStudentMode ? { onclassMentions: selectedMentions, onclassChannels, studentPostType } : {}) });
      }
      if (onSaved) await onSaved();
    } catch (_) {}
  }, [isNew, editName, editFolder, eventFields, item, onSaved]);

  // オンクラスフィールドが変更されたら即DB保存（受講生サポート・既存アイテムのみ）
  useEffect(() => {
    if (!isStudentMode || isNew || !item?.id || !onclassInitializedRef.current) return;
    const timer = setTimeout(() => {
      updateText(activeType, item.id, {
        name: editName.trim() || item.name,
        content: editContent || item.content,
        folder: editFolder,
        onclassMentions: selectedMentions,
        onclassChannels,
        studentPostType,
      }).catch(() => {});
    }, 500);
    return () => clearTimeout(timer);
  }, [selectedMentions, onclassChannels, studentPostType]);

  // コンテンツ保存（新規: Zoom自動作成→イベント作成、編集: 更新）
  const handleSaveContent = useCallback(async () => {
    if (!editName.trim()) { showToast('タイトルを入力してください', 'error'); return; }
    // 新規イベント作成時に日時重複チェック
    if (isNew && !isStudentMode && eventFields.startDate) {
      const dup = await checkDuplicateEvent({ eventDate: eventFields.startDate, eventTime: eventFields.startTime, excludeId: item?.id });
      if (dup.duplicate) { showToast(`⚠️ ${dup.message}`, 'error'); return; }
    }
    setEditSaving(true);
    try {
      let content = editContent;

      // 日時自動調整
      if (eventFields.startDate && apiKey && content.trim()) {
        try {
          const res = await aiAlignDatetime({ text: content, eventDate: eventFields.startDate, eventTime: eventFields.startTime, eventEndTime: eventFields.endTime, apiKey });
          if (res.content) { content = res.content; setEditContent(content); }
        } catch (_) {}
      }

      // 新規作成時: Zoom自動作成
      if (isNew && connectedServices.has('zoom') && eventFields.startDate && !eventFields.zoomUrl) {
        showToast('Zoomミーティング自動作成中...', 'success');
        try {
          await createZoomMeeting(
            { title: editName.trim(), startDate: eventFields.startDate, startTime: eventFields.startTime || '10:00', duration: 120 },
            (ev) => {
              if (ev.type === 'result' && ev.data) {
                const zu = ev.data.zoomUrl || '';
                const zm = ev.data.meetingId || '';
                const zp = ev.data.passcode || '';
                setEventFields((prev) => ({ ...prev, zoomUrl: zu, zoomId: zm, zoomPasscode: zp }));
                const zoomBlock = `\n\n■ Zoom参加情報\n参加URL: ${zu}\nミーティングID: ${zm}\nパスコード: ${zp}`;
                content += zoomBlock;
                saveAppSettings({ lme_zoom_url: zu, lme_meeting_id: zm, lme_passcode: zp }).catch(() => {});
              }
            }
          );
          fetchZoomSettings().then(setZoomList).catch(() => {});
          showToast('Zoom作成完了', 'success');
        } catch (err) { showToast(`Zoom作成失敗: ${err.message}`, 'error'); }
      }

      if (isNew) {
        await createText(activeType, { name: editName.trim(), content, folder: editFolder, eventDate: eventFields.startDate || '', eventTime: eventFields.startTime || '', eventEndTime: eventFields.endTime || '', ...(isStudentMode ? { onclassMentions: selectedMentions, onclassChannels, studentPostType } : {}) });
        showToast('イベント作成完了！下の投稿ボタンで各サイトに投稿できます', 'success');
      } else {
        await updateText(activeType, item.id, { name: editName.trim(), content, folder: editFolder, eventDate: eventFields.startDate || '', eventTime: eventFields.startTime || '', eventEndTime: eventFields.endTime || '', ...(isStudentMode ? { onclassMentions: selectedMentions, onclassChannels, studentPostType } : {}) });
        showToast('保存しました', 'success');
      }

      // Googleカレンダー自動登録（新規 + イベントモード + 日付あり + チェック有効時）
      if (isNew && !isStudentMode && syncToGcal && eventFields.startDate) {
        try {
          const startTime = `${eventFields.startDate}T${eventFields.startTime || '10:00'}:00+09:00`;
          const endTime = `${eventFields.startDate}T${eventFields.endTime || '12:00'}:00+09:00`;
          await createCalendarEvent({ title: editName.trim(), description: content.substring(0, 500), startTime, endTime });
          showToast('Googleカレンダーにも登録しました', 'success');
        } catch (_) {
          // Googleカレンダー未連携時はサイレント
        }
      }

      setEditContent(content);
      if (onSaved) await onSaved();
    } catch (err) { showToast(err.message, 'error'); }
    finally { setEditSaving(false); }
  }, [isNew, editName, editContent, eventFields, apiKey, connectedServices, item, onSaved, showToast, syncToGcal, isStudentMode]);

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
    setSelectedSites((prev) => {
      const adding = !prev.includes(site);
      // 下書き非対応サイトは選択時に自動で公開ON
      if (adding && PUBLISH_ONLY_SITES.has(site)) {
        setPublishSites((ps) => ({ ...ps, [site]: true }));
      }
      return adding ? [...prev, site] : prev.filter((s) => s !== site);
    });
  }

  function updateEventField(key, value) {
    setEventFields((prev) => ({ ...prev, [key]: value }));
  }

  const handlePost = useCallback(async () => {
    if (selectedSites.length === 0) {
      showToast('投稿先サイトを選択してください', 'error');
      return;
    }

    // 投稿前にコンテンツ＋オンクラスフィールドを保存
    try {
      const savePayload = {
        name: editName.trim() || item?.name || '',
        content: editContent || item?.content || '',
        folder: editFolder,
        eventDate: eventFields.startDate || '',
        eventTime: eventFields.startTime || '',
        eventEndTime: eventFields.endTime || '',
        ...(isStudentMode ? { onclassMentions: selectedMentions, onclassChannels, studentPostType } : {}),
      };
      if (isNew) {
        await createText(activeType, savePayload);
      } else if (item?.id) {
        await updateText(activeType, item.id, savePayload);
      }
      if (onSaved) await onSaved();
    } catch (e) {
      showToast(`保存失敗: ${e.message}`, 'error');
      return;
    }

    setPosting(true);
    setLogs([]);
    setSiteStatuses({});
    setPostDone(false);

    // Zoom URLが未設定 かつ オンライン開催 → Zoomミーティングを自動作成
    let currentFields = { ...eventFields };
    const isOnline = !currentFields.place || currentFields.place.includes('オンライン');
    if (isOnline && !currentFields.zoomUrl && connectedServices.has('zoom')) {
      setLogs((prev) => [...prev, { type: 'log', text: '🎥 Zoomミーティングを自動作成中...' }]);
      try {
        let zoomDone = false;
        await createZoomMeeting(
          {
            title: currentFields.zoomTitle || currentFields.title || item?.name || 'ミーティング',
            startDate: currentFields.startDate,
            startTime: currentFields.startTime || '10:00',
            duration: 120,
          },
          (event) => {
            if (event.type === 'log') {
              setLogs((prev) => [...prev, { type: 'log', text: `[Zoom] ${event.message}` }]);
            } else if (event.type === 'error') {
              setLogs((prev) => [...prev, { type: 'error', text: `[Zoom] ${event.message}` }]);
            } else if (event.type === 'result' && event.data) {
              currentFields = {
                ...currentFields,
                zoomTitle: event.data.title || event.data.label || '',
                zoomUrl: event.data.zoomUrl || '',
                zoomId: event.data.meetingId || '',
                zoomPasscode: (event.data.passcode && !/\*/.test(event.data.passcode)) ? event.data.passcode : '',
              };
              setEventFields(currentFields);
              setZoomAutoCreated(true);
              zoomDone = true;
              setLogs((prev) => [...prev, { type: 'log', text: '🎥 ✅ Zoomミーティング作成完了' }]);
            }
          }
        );
        // Zoom設定リスト更新
        fetchZoomSettings().then(setZoomList).catch(() => {});
      } catch (err) {
        setLogs((prev) => [...prev, { type: 'error', text: `[Zoom] 自動作成失敗: ${err.message}（Zoom無しで投稿を続行します）` }]);
      }
    }

    const effectiveSites = selectedSites.map((s) => s === 'LME' ? `LME:${lmeSubType}` : s);
    const ef = {
      ...currentFields,
      lmeAccount: lmeSubType,
      publishSites: publishSites,
      onclassChannels: onclassChannels,
      onclassMentions: selectedMentions,
      studentPostType: studentPostType,
      onclassImagePath: onclassImage?.serverPath || '',
    };

    // Zoom情報は告知文には含めない（各サイトの専用URL欄・メール送信時のみ使用）
    let finalContent = editContent || item?.content || '';

    try {
      await postToSites(
        {
          content: finalContent,
          sites: effectiveSites,
          eventFields: ef,
          generateImage,
          imageStyle,
          openaiApiKey: apiKey,
          dalleApiKey: dalleApiKey || apiKey,
          itemId: item?.id || '',
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
            // 投稿履歴を取得してサイトカードに反映
            if (item?.id) {
              setTimeout(() => {
                fetchPostingHistory(item.id).then((history) => {
                  const map = {};
                  history.forEach((h) => { map[h.siteName] = h; });
                  setPostingHistoryMap(map);
                  if (history.length > 0) {
                    const lines = history.map((h) => {
                      const icon = h.status === 'error' ? '❌' : h.published ? '✅' : '📝';
                      const label = `${icon} ${h.siteLabel}`;
                      return h.eventUrl ? `${label}: ${h.eventUrl}` : `${label}: (URL未取得)`;
                    });
                    setLogs((prev) => [
                      ...prev,
                      { type: 'log', text: '' },
                      { type: 'success', text: '📋 投稿結果一覧:' },
                      ...lines.map((l) => ({ type: 'log', text: l })),
                    ]);
                  }
                }).catch(() => {});
              }, 2000); // PostJobのDB書き込み完了を待つ
            }
          }
        }
      );
    } catch (err) {
      setLogs((prev) => [...prev, { type: 'error', text: `エラー: ${err.message}` }]);
      showToast(err.message, 'error');
    } finally {
      setPosting(false);
    }
  }, [selectedSites, lmeSubType, eventFields, generateImage, imageStyle, apiKey, item, showToast, connectedServices]);

  // オーバーレイクリックではモーダルを閉じない（✕ボタンとキャンセルボタンのみ）
  function handleOverlayClick() {}

  // Escapeキーでもモーダルを閉じない

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
          <h2 className="modal-title" style={{ flex: 1 }}>{isNew ? '新規作成' : item?.name}</h2>
          <button className="modal-close" onClick={onClose} disabled={posting || editSaving}>✕</button>
        </div>

        <div className="modal-body">
          {/* ===== コンテンツ編集セクション ===== */}
              {/* Name + Generate button — EditModalと完全同一 */}
              <div className="form-group">
                <label className="form-label">
                  名前 <span className="form-label-required">*</span>
                </label>
                <div className="name-generate-row">
                  <input
                    className="form-input"
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    placeholder="テキスト名を入力"
                    disabled={posting || editSaving}
                  />
                  {!isGitReview && <button
                    className="ai-btn ai-btn-generate"
                    onClick={async () => {
                      if (!editName.trim()) { showToast('名前（タイトル）を入力してください', 'error'); return; }
                      if (!eventFields.startDate) { showToast('開催日を入力してください', 'error'); return; }
                      // 日時重複チェック
                      if (!isStudentMode && isNew) {
                        const dup = await checkDuplicateEvent({ eventDate: eventFields.startDate, eventTime: eventFields.startTime, excludeId: item?.id });
                        if (dup.duplicate) { showToast(`⚠️ ${dup.message}`, 'error'); return; }
                      }
                      setAiLoading('generate');
                      try {
                        const data = await aiGenerate({ title: editName.trim(), type: 'event', apiKey, eventDate: eventFields.startDate, eventTime: eventFields.startTime, eventEndTime: eventFields.endTime });
                        if (data.content) {
                          setEditContent(data.content);
                          await autoSave(data.content);
                          showToast('生成・保存完了', 'success');
                        }
                      } catch (err) { showToast(err.message, 'error'); }
                      finally { setAiLoading(''); }
                    }}
                    disabled={!!aiLoading || posting}
                    title="タイトルに沿って文章を自動生成"
                  >
                    {aiLoading === 'generate' ? <span className="spinner" /> : '✨'} 文章自動生成
                  </button>}
                </div>
              </div>

              {/* フォルダ選択 */}
              {folders.length > 0 && (
                <div className="form-group">
                  <label className="form-label">フォルダ</label>
                  <select
                    className="form-input"
                    value={editFolder}
                    onChange={(e) => setEditFolder(e.target.value)}
                    disabled={posting || editSaving}
                  >
                    <option value="">未分類</option>
                    {folders.map((f) => (
                      <optgroup key={f.name} label={f.name}>
                        <option value={f.name}>{f.name}</option>
                        {(f.children || []).map((child) => (
                          <option key={`${f.name}/${child}`} value={`${f.name}/${child}`}>
                            {f.name} / {child}
                          </option>
                        ))}
                      </optgroup>
                    ))}
                  </select>
                </div>
              )}

              {/* オンクラス設定（受講生サポート時のみ、Gitレビューでは非表示） */}
              {isStudentMode && !isGitReview && (
                <div className="form-group" style={{ marginTop: '12px', padding: '12px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0' }}>
                  <label className="form-label" style={{ fontWeight: 'bold', marginBottom: '8px' }}>オンクラス設定</label>

                  {/* 種別フラグ */}
                  <div style={{ display: 'flex', gap: '12px', marginBottom: '10px' }}>
                    {['受講生告知', 'イベント'].map((type) => (
                      <label key={type} style={{ display: 'flex', alignItems: 'center', gap: '6px', cursor: 'pointer', fontSize: '13px' }}>
                        <input
                          type="radio"
                          name="studentPostType"
                          value={type}
                          checked={studentPostType === type}
                          onChange={() => setStudentPostType(type)}
                          disabled={posting}
                        />
                        {type}
                      </label>
                    ))}
                  </div>

                  {/* チャンネル選択 */}
                  <div style={{ marginBottom: '10px' }}>
                    <label className="form-label" style={{ fontSize: '12px' }}>チャンネル</label>
                    <div style={{ position: 'relative' }}>
                      <div
                        className="form-input"
                        style={{ cursor: 'pointer', minHeight: '32px', display: 'flex', flexWrap: 'wrap', gap: '4px', alignItems: 'center', padding: '4px 8px' }}
                        onClick={() => !posting && setChannelDropdownOpen(!channelDropdownOpen)}
                      >
                        {onclassChannels.length > 0
                          ? onclassChannels.map((ch) => (
                              <span key={ch} style={{ background: '#e0e7ff', color: '#3730a3', padding: '2px 8px', borderRadius: '12px', fontSize: '11px', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                                {ch}
                                <span style={{ cursor: 'pointer', fontWeight: 'bold' }} onClick={(e) => { e.stopPropagation(); setOnclassChannels((prev) => prev.filter((c) => c !== ch)); }}>×</span>
                              </span>
                            ))
                          : <span style={{ color: '#9ca3af', fontSize: '12px' }}>チャンネルを選択...</span>}
                      </div>
                      {channelDropdownOpen && (
                        <>
                        <div style={{ position: 'fixed', inset: 0, zIndex: 99 }} onClick={() => setChannelDropdownOpen(false)} />
                        <div style={{ position: 'absolute', top: '100%', left: 0, right: 0, background: '#fff', border: '1px solid #d1d5db', borderRadius: '6px', boxShadow: '0 4px 12px rgba(0,0,0,0.15)', zIndex: 100, maxHeight: '200px', overflowY: 'auto' }}>
                          {ONCLASS_CHANNELS.map((ch) => (
                            <label key={ch} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '6px 12px', cursor: 'pointer', fontSize: '12px', borderBottom: '1px solid #f3f4f6' }}
                              onMouseEnter={(e) => (e.currentTarget.style.background = '#f0f4ff')}
                              onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}>
                              <input type="checkbox" checked={onclassChannels.includes(ch)} onChange={() => setOnclassChannels((prev) => prev.includes(ch) ? prev.filter((c) => c !== ch) : [...prev, ch])} />
                              {ch}
                            </label>
                          ))}
                        </div>
                        </>
                      )}
                    </div>
                  </div>

                  {/* メンション対象 */}
                  <div>
                    <label className="form-label" style={{ fontSize: '12px' }}>
                      メンション対象
                      {studentsLoading && <span style={{ color: '#6b7280', fontSize: '11px', marginLeft: '8px' }}>取得中...</span>}
                      {!studentsLoading && onclassStudents.length > 0 && (
                        <span style={{ color: '#6b7280', fontSize: '11px', marginLeft: '8px' }}>
                          {selectedMentions.length}/{onclassStudents.length}名
                          <button type="button" style={{ marginLeft: '6px', fontSize: '10px', color: '#3b82f6', background: 'none', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}
                            onClick={() => setSelectedMentions([...onclassStudents])}>
                            全選択
                          </button>
                          <button type="button" style={{ marginLeft: '4px', fontSize: '10px', color: '#dc2626', background: 'none', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}
                            onClick={() => setSelectedMentions([])}>
                            クリア
                          </button>
                          <button type="button" style={{ marginLeft: '4px', fontSize: '10px', color: '#6b7280', background: 'none', border: 'none', cursor: 'pointer' }}
                            onClick={() => loadOnclassStudents(true)} disabled={studentsLoading} title="最新データ取得">🔄</button>
                        </span>
                      )}
                    </label>
                    <div style={{ position: 'relative' }}>
                      <div className="form-input"
                        style={{ cursor: 'pointer', minHeight: '32px', display: 'flex', flexWrap: 'wrap', gap: '3px', alignItems: 'center', padding: '4px 8px', maxHeight: '80px', overflowY: 'auto' }}
                        onClick={() => !posting && !studentsLoading && setMentionDropdownOpen(!mentionDropdownOpen)}>
                        {studentsLoading
                          ? <span style={{ color: '#9ca3af', fontSize: '12px' }}>取得中...</span>
                          : selectedMentions.length > 0
                            ? selectedMentions.map((name) => (
                                <span key={name} style={{ background: '#dbeafe', color: '#1e40af', padding: '1px 6px', borderRadius: '10px', fontSize: '10px', display: 'inline-flex', alignItems: 'center', gap: '3px' }}>
                                  @{name}
                                  <span style={{ cursor: 'pointer', fontWeight: 'bold' }} onClick={(e) => { e.stopPropagation(); setSelectedMentions((prev) => prev.filter((n) => n !== name)); }}>×</span>
                                </span>
                              ))
                            : <span style={{ color: '#9ca3af', fontSize: '12px' }}>メンション対象を選択...</span>}
                      </div>
                      {mentionDropdownOpen && (
                        <>
                        <div style={{ position: 'fixed', inset: 0, zIndex: 99 }} onClick={() => setMentionDropdownOpen(false)} />
                        <div style={{ position: 'absolute', top: '100%', left: 0, right: 0, background: '#fff', border: '1px solid #d1d5db', borderRadius: '6px', boxShadow: '0 4px 12px rgba(0,0,0,0.15)', zIndex: 100, maxHeight: '200px', overflowY: 'auto' }}>
                          {onclassStudents.map((name) => (
                            <label key={name} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '5px 12px', cursor: 'pointer', fontSize: '12px', borderBottom: '1px solid #f3f4f6' }}
                              onMouseEnter={(e) => (e.currentTarget.style.background = '#eff6ff')}
                              onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}>
                              <input type="checkbox" checked={selectedMentions.includes(name)}
                                onChange={() => setSelectedMentions((prev) => prev.includes(name) ? prev.filter((n) => n !== name) : [...prev, name])} />
                              @{name}
                            </label>
                          ))}
                        </div>
                        </>
                      )}
                    </div>
                  </div>

                  {/* 画像添付（1枚のみ） */}
                  <div style={{ marginTop: '10px' }}>
                    <label className="form-label" style={{ fontSize: '12px' }}>画像添付（1枚）</label>
                    <input
                      ref={imageInputRef}
                      type="file"
                      accept="image/jpeg,image/png,image/gif"
                      style={{ display: 'none' }}
                      onChange={async (e) => {
                        const file = e.target.files?.[0];
                        if (!file) return;
                        const preview = URL.createObjectURL(file);
                        setOnclassImage({ file, preview, serverPath: null });
                        try {
                          const data = await uploadOnclassImage(file);
                          setOnclassImage((prev) => prev ? { ...prev, serverPath: data.path } : null);
                        } catch (err) {
                          showToast(`画像アップロード失敗: ${err.message}`, 'error');
                        }
                      }}
                    />
                    {onclassImage ? (
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <img src={onclassImage.preview} alt="添付画像" style={{ width: '60px', height: '60px', objectFit: 'cover', borderRadius: '6px', border: '1px solid #d1d5db' }} />
                        <div>
                          <span style={{ fontSize: '11px', color: '#6b7280' }}>{onclassImage.file.name}</span>
                          <button type="button" style={{ marginLeft: '8px', fontSize: '11px', color: '#dc2626', background: 'none', border: 'none', cursor: 'pointer' }}
                            onClick={() => { setOnclassImage(null); if (imageInputRef.current) imageInputRef.current.value = ''; }}>
                            削除
                          </button>
                        </div>
                      </div>
                    ) : (
                      <button type="button" className="btn btn-sm" style={{ fontSize: '12px' }}
                        onClick={() => imageInputRef.current?.click()} disabled={posting}>
                        📷 画像を選択
                      </button>
                    )}
                  </div>
                </div>
              )}

              {/* Datetime section for AI — Gitレビューでは非表示 */}
              {!isGitReview && <div className="datetime-section">
                <p className="datetime-section-label">AI文章生成用の日時設定</p>
                <div className="form-row-3">
                  <div className="form-group">
                    <label className="form-label">開催日</label>
                    <input className="form-input" type="date" value={eventFields.startDate} onChange={(e) => handleStartDateChange(e.target.value)} disabled={posting} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">開始時刻</label>
                    <input className="form-input" type="time" value={eventFields.startTime} onChange={(e) => updateEventField('startTime', e.target.value)} disabled={posting} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">終了時刻</label>
                    <input className="form-input" type="time" value={eventFields.endTime} onChange={(e) => updateEventField('endTime', e.target.value)} disabled={posting} />
                  </div>
                </div>

                {/* API Key */}
                <div className="form-group" style={{ marginTop: '10px' }}>
                  <label className="form-label">OpenAI APIキー</label>
                  <input
                    className="form-input"
                    type="password"
                    value={apiKey}
                    onChange={(e) => setApiKey(e.target.value)}
                    placeholder="sk-..."
                    disabled={posting}
                  />
                </div>
              </div>}

              {/* AI Buttons — Gitレビューでは非表示 */}
              {!isGitReview && <>
              <div className="ai-buttons">
                <button className="ai-btn ai-btn-correct" onClick={async () => { if (!editContent.trim()) return; setAiLoading('correct'); try { const d = await aiCorrect({ text: editContent, apiKey }); if (d.corrected) { setEditContent(d.corrected); await autoSave(d.corrected); showToast('校正・保存完了', 'success'); } } catch (e) { showToast(e.message, 'error'); } finally { setAiLoading(''); } }} disabled={!!aiLoading}>
                  {aiLoading === 'correct' ? <span className="spinner" /> : '✅'} 文章校正
                </button>
                <button className="ai-btn ai-btn-align" onClick={async () => { if (!editContent.trim() || !eventFields.startDate) return; setAiLoading('align'); try { const d = await aiAlignDatetime({ text: editContent, eventDate: eventFields.startDate, eventTime: eventFields.startTime, eventEndTime: eventFields.endTime, apiKey }); if (d.content) { setEditContent(d.content); await autoSave(d.content); showToast('日時調整・保存完了', 'success'); } } catch (e) { showToast(e.message, 'error'); } finally { setAiLoading(''); } }} disabled={!!aiLoading}>
                  {aiLoading === 'align' ? <span className="spinner" /> : '📅'} 日時を合わせる
                </button>
                <button className={`ai-btn ai-btn-voice${isRecording ? ' recording' : ''}`} onClick={handleVoice} title="音声入力">
                  🎤 {isRecording ? '録音中...' : '音声入力'}
                </button>
                <button className="ai-btn ai-btn-agent" onClick={() => setShowAgent(!showAgent)} disabled={!!aiLoading && aiLoading !== 'agent'}>
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
                    onKeyDown={(e) => { if (e.key === 'Enter') { if (!agentPrompt.trim() || !editContent.trim()) return; setAiLoading('agent'); aiAgent({ text: editContent, prompt: agentPrompt, apiKey }).then(async (d) => { if (d.result) { setEditContent(d.result); await autoSave(d.result); showToast('エージェント・保存完了', 'success'); } }).catch((err) => showToast(err.message, 'error')).finally(() => setAiLoading('')); } }}
                  />
                  <button
                    className="ai-btn ai-btn-agent"
                    onClick={async () => { if (!agentPrompt.trim() || !editContent.trim()) return; setAiLoading('agent'); try { const d = await aiAgent({ text: editContent, prompt: agentPrompt, apiKey }); if (d.result) { setEditContent(d.result); await autoSave(d.result); showToast('エージェント・保存完了', 'success'); } } catch (e) { showToast(e.message, 'error'); } finally { setAiLoading(''); } }}
                    disabled={!!aiLoading}
                  >
                    実行
                  </button>
                </div>
              )}
              </>}

              {/* Content — ドラッグ&ドロップ画像対応 */}
              <div className="form-group">
                <label className="form-label">内容 <span style={{ fontSize: '11px', color: '#9ca3af', fontWeight: 400 }}>（画像をドラッグ&ドロップまたはペーストで挿入可能）</span></label>
                <div
                  style={{ position: 'relative', width: '100%' }}
                  onDragOver={(e) => { e.preventDefault(); e.currentTarget.style.outline = '2px dashed #7c3aed'; }}
                  onDragLeave={(e) => { e.currentTarget.style.outline = 'none'; }}
                  onDrop={async (e) => {
                    e.preventDefault();
                    e.currentTarget.style.outline = 'none';
                    const files = [...e.dataTransfer.files].filter(f => f.type.startsWith('image/'));
                    for (const file of files) {
                      try {
                        showToast('📸 画像アップロード中...', 'info');
                        const { url } = await uploadImage(file);
                        insertAtCursor(`\n![${file.name}](${url})\n`);
                        showToast('画像を挿入しました', 'success');
                      } catch (err) { showToast(err.message, 'error'); }
                    }
                  }}
                >
                  <textarea
                    ref={contentTextareaRef}
                    className="form-textarea tall"
                    style={{ width: '100%', display: 'block' }}
                    value={editContent}
                    onChange={(e) => setEditContent(e.target.value)}
                    placeholder="テキスト内容を入力してください（画像をドラッグ&ドロップ可能）"
                    disabled={posting || editSaving}
                    onPaste={async (e) => {
                      const items = [...(e.clipboardData?.items || [])];
                      const imageItem = items.find(i => i.type.startsWith('image/'));
                      if (!imageItem) return;
                      e.preventDefault();
                      const file = imageItem.getAsFile();
                      if (!file) return;
                      try {
                        showToast('📸 画像アップロード中...', 'info');
                        const { url } = await uploadImage(file);
                        insertAtCursor(`\n![pasted-image](${url})\n`);
                        showToast('画像を挿入しました', 'success');
                      } catch (err) { showToast(err.message, 'error'); }
                    }}
                  />
                </div>
              </div>

              <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end', alignItems: 'center', marginTop: '4px' }}>
                {!isStudentMode && isNew && (
                  <label style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '12px', color: '#16a34a', cursor: 'pointer', marginRight: 'auto' }}>
                    <input type="checkbox" checked={syncToGcal} onChange={(e) => setSyncToGcal(e.target.checked)} />
                    📅 Googleカレンダーにも登録
                  </label>
                )}
                <button
                  className="btn btn-primary"
                  onClick={handleSaveContent}
                  disabled={posting || editSaving || !editName.trim()}
                >
                  {editSaving ? '⏳ 保存中...' : '💾 保存'}
                </button>
              </div>

          {/* ===== 投稿設定セクション ===== */}
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
                      {PUBLISH_ONLY_SITES.has(site) ? (
                        <span
                          className="publish-toggle publish-on"
                          style={{ cursor: 'default', opacity: 0.7, fontSize: '10px' }}
                          title="このサイトは下書き非対応（チェック=公開投稿）"
                        >
                          公開のみ
                        </span>
                      ) : (
                        <button
                          type="button"
                          className={`publish-toggle ${publishSites[site] ? 'publish-on' : 'publish-off'}`}
                          onClick={(e) => {
                            e.stopPropagation();
                            if (!posting) setPublishSites((prev) => ({ ...prev, [site]: !prev[site] }));
                          }}
                          disabled={posting}
                          title={publishSites[site] ? '公開する' : '下書き保存'}
                        >
                          {publishSites[site] ? '公開' : '下書き'}
                        </button>
                      )}
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
                    {/* 投稿済みイベントURL */}
                    {postingHistoryMap[SITE_TO_SERVICE[site]] && (
                      <div style={{ padding: '2px 6px 4px 6px', fontSize: '10px' }}>
                        {postingHistoryMap[SITE_TO_SERVICE[site]].eventUrl ? (
                          <a
                            href={postingHistoryMap[SITE_TO_SERVICE[site]].eventUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            style={{ color: '#3b82f6', textDecoration: 'none', display: 'inline-flex', alignItems: 'center', gap: '3px' }}
                            onClick={(e) => e.stopPropagation()}
                          >
                            🔗 {postingHistoryMap[SITE_TO_SERVICE[site]].published ? '公開中' : '下書き'}
                            <span style={{ color: '#9ca3af', fontSize: '10px', marginLeft: '4px' }}>
                              {new Date(postingHistoryMap[SITE_TO_SERVICE[site]].postedAt).toLocaleDateString('ja-JP')}
                            </span>
                          </a>
                        ) : (
                          <span style={{ color: postingHistoryMap[SITE_TO_SERVICE[site]].status === 'error' ? '#dc2626' : '#9ca3af' }}>
                            {postingHistoryMap[SITE_TO_SERVICE[site]].status === 'error'
                              ? `❌ ${postingHistoryMap[SITE_TO_SERVICE[site]].errorMessage || 'エラー'}`
                              : '📝 投稿済み（URL未取得）'}
                          </span>
                        )}
                      </div>
                    )}
                    {/* Gmail送信先 */}
                    {site === 'Gmail' && isChecked && (
                      <div className="lme-sub-options">
                        <div style={{ marginTop: '4px' }}>
                          <span className="lme-senddate-label">送信先</span>
                          <input
                            className="form-input"
                            type="text"
                            value={eventFields.gmailTo}
                            onChange={(e) => updateEventField('gmailTo', e.target.value)}
                            placeholder="email1@example.com, email2@example.com"
                            disabled={posting}
                            style={{ width: '100%', fontSize: '12px' }}
                          />
                        </div>
                      </div>
                    )}
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

            {/* Zoom Section (受講生サポートモードでは非表示) */}
            {!isStudentMode && <div className="zoom-section" style={{ marginTop: '10px', background: '#f0f7ff', border: '1.5px solid #bfdbfe', borderRadius: '10px', padding: '14px' }}>
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
                  {!zoomAutoCreated && (
                    <button
                      type="button"
                      className="btn btn-sm zoom-save-btn"
                      onClick={handleSaveZoom}
                      disabled={posting || zoomSaving || zoomCreating || !eventFields.zoomUrl}
                      title="現在のZoom設定をDBに保存"
                    >
                      {zoomSaving ? <span className="spinner" /> : '💾'} 保存
                    </button>
                  )}
                  {zoomAutoCreated && (
                    <button
                      type="button"
                      className="btn btn-sm"
                      onClick={() => {
                        setZoomAutoCreated(false);
                        setEventFields((prev) => ({
                          ...prev, zoomTitle: '', zoomUrl: '', zoomId: '', zoomPasscode: '',
                        }));
                      }}
                      disabled={posting || zoomCreating}
                      title="自動作成されたZoom情報をクリアして手動入力に戻す"
                      style={{ background: '#fee2e2', color: '#991b1b', border: '1px solid #fca5a5' }}
                    >
                      🗑 クリア
                    </button>
                  )}
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

              {/* Zoom URL保存済み & 編集モードでない → 詳細ビュー */}
              {eventFields.zoomUrl && !zoomEditing && !zoomCreating ? (
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
                    <span style={{ fontSize: '13px', fontWeight: 600, color: '#1e40af' }}>
                      🎥 Zoom 詳細
                    </span>
                    <button
                      type="button"
                      className="btn btn-sm"
                      onClick={() => setZoomEditing(true)}
                      disabled={posting}
                      style={{ fontSize: '11px' }}
                    >
                      ✏️ 編集
                    </button>
                  </div>

                  {eventFields.zoomTitle && (
                    <div style={{ fontSize: '13px', fontWeight: 600, color: '#334155', marginBottom: '6px' }}>
                      {eventFields.zoomTitle}
                    </div>
                  )}

                  <div style={{ padding: '10px 12px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0' }}>
                    <div style={{ marginBottom: '6px' }}>
                      <span style={{ fontSize: '11px', color: '#64748b' }}>URL</span>
                      <a
                        href={eventFields.zoomUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        style={{ display: 'block', color: '#2563eb', fontSize: '13px', wordBreak: 'break-all', textDecoration: 'underline' }}
                      >
                        {eventFields.zoomUrl}
                      </a>
                    </div>
                    {eventFields.zoomId && (
                      <div style={{ marginBottom: '4px' }}>
                        <span style={{ fontSize: '11px', color: '#64748b' }}>ミーティングID: </span>
                        <span style={{ fontSize: '13px', color: '#334155', fontFamily: 'monospace' }}>{eventFields.zoomId}</span>
                      </div>
                    )}
                    {eventFields.zoomPasscode && (
                      <div>
                        <span style={{ fontSize: '11px', color: '#64748b' }}>パスコード: </span>
                        <span style={{ fontSize: '13px', color: '#334155', fontFamily: 'monospace' }}>
                          {showPasscode ? eventFields.zoomPasscode : '••••••'}
                        </span>
                        <button
                          type="button"
                          onClick={() => setShowPasscode(!showPasscode)}
                          style={{ marginLeft: '6px', background: 'none', border: 'none', cursor: 'pointer', fontSize: '12px' }}
                        >
                          {showPasscode ? '🙈' : '👁️'}
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              ) : (
                /* Zoom URL未保存 or 編集モード → フォーム */
                <div>
                  {zoomEditing && (
                    <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: '6px' }}>
                      <button
                        type="button"
                        className="btn btn-sm"
                        onClick={() => setZoomEditing(false)}
                        style={{ fontSize: '11px' }}
                      >
                        ← 詳細に戻る
                      </button>
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
              )}
            </div>}

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

          {/* API Keys */}
          <div className="api-key-section">
            <p className="api-key-label">OpenAI APIキー（文章生成・校正・日時調整）</p>
            <input
              className="api-key-input"
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="sk-..."
              disabled={posting}
            />
            <p className="api-key-label" style={{ marginTop: '8px' }}>DALL-E 3 APIキー（画像生成用・未入力時は上のキーを使用）</p>
            <input
              className="api-key-input"
              type="password"
              value={dalleApiKey}
              onChange={(e) => setDalleApiKey(e.target.value)}
              placeholder="sk-...（空欄の場合はOpenAIキーを使用）"
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
                    {log.text?.split(/(https?:\/\/[^\s]+)/g).map((part, j) =>
                      /^https?:\/\//.test(part) ? (
                        <a key={j} href={part} target="_blank" rel="noopener noreferrer" style={{ color: '#3b82f6', textDecoration: 'underline' }}>{part}</a>
                      ) : part
                    ) || log.text}
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
