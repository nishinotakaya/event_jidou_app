import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import { saveAppSettings } from './api.js'

// ワンタイム: localStorage → DB移行
const LS_MIGRATION_KEY = 'db_migration_done';
if (!localStorage.getItem(LS_MIGRATION_KEY)) {
  const keys = [
    ['event_gen_date', 'event_gen_date'],
    ['event_gen_time', 'event_gen_time'],
    ['event_gen_end_time', 'event_gen_end_time'],
    ['openai_api_key', 'openai_api_key'],
    ['lme_gen_checked', 'lme_gen_checked'],
    ['lme_gen_subtype', 'lme_gen_subtype'],
    ['lme_send_date', 'lme_send_date'],
    ['lme_send_time', 'lme_send_time'],
    ['lme_zoom_url', 'lme_zoom_url'],
    ['lme_meeting_id', 'lme_meeting_id'],
    ['lme_passcode', 'lme_passcode'],
    ['post_selected_sites', 'post_selected_sites'],
  ];
  const pairs = {};
  keys.forEach(([lsKey, dbKey]) => {
    const val = localStorage.getItem(lsKey);
    if (val) pairs[dbKey] = val;
  });
  if (Object.keys(pairs).length > 0) {
    saveAppSettings(pairs)
      .then(() => {
        console.log('[Migration] localStorage → DB 移行完了:', Object.keys(pairs));
        localStorage.setItem(LS_MIGRATION_KEY, 'true');
      })
      .catch((e) => console.error('[Migration] 移行失敗:', e));
  } else {
    localStorage.setItem(LS_MIGRATION_KEY, 'true');
  }
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
