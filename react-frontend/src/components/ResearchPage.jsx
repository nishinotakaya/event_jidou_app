import { useState } from 'react';
import { searchCrossSiteEvents, searchViaBrowserFallback } from '../api.js';

// バックエンド Api::ResearchController::SERVICES と対応
const SITES = [
  { key: 'kokuchpro', label: 'こくちーずプロ', color: '#e67e22' },
  { key: 'peatix', label: 'Peatix', color: '#27ae60' },
  { key: 'connpass', label: 'connpass', color: '#c0392b' },
  { key: 'techplay', label: 'TechPlay', color: '#2980b9' },
  { key: 'doorkeeper', label: 'Doorkeeper', color: '#8e44ad' },
  { key: 'jimoty', label: 'ジモティー', color: '#16a085' },
  // 下2つはサイト側にフリーワード検索が無いため、キーワードに関係なく交流会カテゴリの開催予定を全件表示する
  { key: 'evenz', label: 'e-venz', color: '#d35400', note: 'キーワード非対応（異業種交流会カテゴリを全件表示）' },
  { key: 'doomo', label: 'Doomo', color: '#34495e', note: 'キーワード非対応（ビジネス交流会の開催予定を全件表示）' },
];

// バックエンド Research::BaseService::LOCATION_ALIASES のキーと対応
const LOCATIONS = [
  { key: 'online', label: 'オンライン' },
  { key: '東京', label: '東京' },
  { key: '神奈川', label: '神奈川' },
  { key: '千葉', label: '千葉' },
  { key: '埼玉', label: '埼玉' },
  { key: '大阪', label: '大阪' },
  { key: '京都', label: '京都' },
  { key: '兵庫', label: '兵庫' },
  { key: '愛知', label: '愛知' },
  { key: '福岡', label: '福岡' },
  { key: '北海道', label: '北海道' },
  { key: '沖縄', label: '沖縄' },
];

// 経営者・ビジネス系の定番キーワード（ワンタップで検索）
const PRESET_KEYWORDS = [
  '経営者 交流会',
  '異業種交流会',
  'ビジネス交流会',
  '起業家 交流会',
  '経営者 朝活',
  '名刺交換会',
];

export default function ResearchPage({ showToast }) {
  const [keyword, setKeyword] = useState('経営者 交流会');
  const [selectedSites, setSelectedSites] = useState(SITES.map((s) => s.key));
  const [selectedLocations, setSelectedLocations] = useState([]); // 空 = 全国
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState(null); // null=未検索
  const [siteErrors, setSiteErrors] = useState({});
  const [countsBySite, setCountsBySite] = useState({});
  const [siteFilter, setSiteFilter] = useState('all'); // 結果一覧の絞り込み

  function toggleSite(key) {
    setSelectedSites((prev) =>
      prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]
    );
  }

  function toggleLocation(key) {
    setSelectedLocations((prev) =>
      prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]
    );
  }

  async function handleSearch(searchKeyword = keyword) {
    const trimmed = (searchKeyword || '').trim();
    if (!trimmed) {
      showToast('キーワードを入力してください', 'error');
      return;
    }
    if (selectedSites.length === 0) {
      showToast('検索するサイトを1つ以上選択してください', 'error');
      return;
    }
    setSearching(true);
    setSiteFilter('all');
    try {
      const data = await searchCrossSiteEvents({ keyword: trimmed, sites: selectedSites, locations: selectedLocations });
      const { results: mergedResults, errors, counts } = await retryBlockedSitesFromBrowser(data);
      setResults(mergedResults);
      setSiteErrors(errors);
      setCountsBySite(counts);
      const errorCount = Object.keys(errors).length;
      if (errorCount > 0) {
        showToast(`${errorCount}サイトで検索に失敗しました（他サイトの結果は表示中）`, 'error');
      } else {
        showToast(`${mergedResults.length}件見つかりました`, 'success');
      }
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setSearching(false);
    }
  }

  // Peatix のようにサーバー（Heroku）のIPを弾くサイトは、ブラウザ（＝自分の回線）から取り直して合流させる
  async function retryBlockedSitesFromBrowser(data) {
    const errors = { ...(data.errors || {}) };
    const counts = { ...(data.countsBySite || {}) };
    const fallbackEntries = Object.entries(data.browserFallbacks || {});

    const retried = await Promise.all(
      fallbackEntries.map(async ([site, fallback]) => {
        try {
          const siteResults = await searchViaBrowserFallback({ site, fallback, locations: selectedLocations });
          counts[site] = siteResults.length;
          delete errors[site];
          return siteResults;
        } catch (err) {
          errors[site] = `${errors[site]}（ブラウザからの再取得も失敗: ${err.message}）`;
          return [];
        }
      })
    );

    const results = [...(data.results || []), ...retried.flat()].sort((a, b) =>
      (a.startsAt || '9999-12-31').localeCompare(b.startsAt || '9999-12-31')
    );
    return { results, errors, counts };
  }

  const siteMeta = Object.fromEntries(SITES.map((s) => [s.key, s]));
  const visibleResults = (results || []).filter(
    (r) => siteFilter === 'all' || r.site === siteFilter
  );

  return (
    <div style={{ padding: '0 24px 24px' }}>
      {/* 検索条件 */}
      <div style={{ borderRadius: '12px', border: '1.5px solid #e2d9f3', background: '#faf8ff', padding: '16px', marginBottom: '16px' }}>
        <div style={{ fontSize: '13px', fontWeight: 600, color: '#5b21b6', marginBottom: '8px' }}>
          🔎 交流会リサーチ — 複数サイトを一斉検索
        </div>

        {/* キーワード入力 + 検索ボタン */}
        <div style={{ display: 'flex', gap: '8px', marginBottom: '10px' }}>
          <input
            type="text"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !searching) handleSearch(); }}
            placeholder="例: 経営者 交流会"
            style={{ flex: 1, padding: '8px 12px', borderRadius: '8px', border: '1px solid #d1d5db', fontSize: '14px' }}
          />
          <button
            className="btn btn-primary"
            onClick={() => handleSearch()}
            disabled={searching}
            style={{ minWidth: '110px' }}
          >
            {searching ? '検索中...' : '一斉検索'}
          </button>
        </div>

        {/* プリセットキーワード */}
        <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', marginBottom: '10px' }}>
          {PRESET_KEYWORDS.map((preset) => (
            <button
              key={preset}
              type="button"
              disabled={searching}
              onClick={() => { setKeyword(preset); handleSearch(preset); }}
              style={{ padding: '4px 10px', borderRadius: '999px', border: '1px solid #c4b5fd', background: keyword === preset ? '#ede9fe' : '#fff', color: '#6d28d9', fontSize: '12px', cursor: 'pointer' }}
            >
              {preset}
            </button>
          ))}
        </div>

        {/* サイト選択 */}
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center', marginBottom: '10px' }}>
          <span style={{ fontSize: '12px', color: '#6b7280' }}>検索先:</span>
          {SITES.map((site) => (
            <label key={site.key} title={site.note || ''} style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '13px', cursor: 'pointer' }}>
              <input
                type="checkbox"
                checked={selectedSites.includes(site.key)}
                onChange={() => toggleSite(site.key)}
              />
              <span style={{ color: site.color, fontWeight: 600 }}>{site.label}</span>
              {site.note && <span style={{ fontSize: '11px', color: '#9ca3af' }}>*</span>}
            </label>
          ))}
        </div>

        {/* 場所選択（複数可・未選択 = 全国） */}
        <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', alignItems: 'center' }}>
          <span style={{ fontSize: '12px', color: '#6b7280' }}>場所:</span>
          {LOCATIONS.map((location) => {
            const selected = selectedLocations.includes(location.key);
            return (
              <button
                key={location.key}
                type="button"
                onClick={() => toggleLocation(location.key)}
                style={{ padding: '3px 10px', borderRadius: '999px', border: '1px solid #86efac', background: selected ? '#16a34a' : '#fff', color: selected ? '#fff' : '#15803d', fontSize: '12px', fontWeight: selected ? 600 : 400, cursor: 'pointer' }}
              >
                {location.key === 'online' ? '💻 ' : '📍 '}{location.label}
              </button>
            );
          })}
          {selectedLocations.length === 0 && (
            <span style={{ fontSize: '11px', color: '#9ca3af' }}>（未選択 = 全国）</span>
          )}
        </div>
      </div>

      {/* サイト別エラー表示 */}
      {Object.keys(siteErrors).length > 0 && (
        <div style={{ borderRadius: '8px', border: '1px solid #fecaca', background: '#fef2f2', padding: '10px 14px', marginBottom: '12px', fontSize: '12px', color: '#b91c1c' }}>
          {Object.entries(siteErrors).map(([siteKey, message]) => (
            <div key={siteKey}>⚠️ {siteMeta[siteKey]?.label || siteKey}: {message}</div>
          ))}
        </div>
      )}

      {/* 結果一覧 */}
      {results !== null && (
        <>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap', marginBottom: '10px' }}>
            <span style={{ fontSize: '13px', fontWeight: 600, color: '#374151' }}>
              検索結果 {results.length}件
            </span>
            <button
              type="button"
              onClick={() => setSiteFilter('all')}
              style={{ padding: '3px 10px', borderRadius: '999px', border: '1px solid #d1d5db', background: siteFilter === 'all' ? '#374151' : '#fff', color: siteFilter === 'all' ? '#fff' : '#374151', fontSize: '12px', cursor: 'pointer' }}
            >
              すべて
            </button>
            {SITES.filter((s) => countsBySite[s.key] !== undefined).map((site) => (
              <button
                key={site.key}
                type="button"
                onClick={() => setSiteFilter(site.key)}
                style={{ padding: '3px 10px', borderRadius: '999px', border: `1px solid ${site.color}`, background: siteFilter === site.key ? site.color : '#fff', color: siteFilter === site.key ? '#fff' : site.color, fontSize: '12px', cursor: 'pointer' }}
              >
                {site.label} {countsBySite[site.key]}
              </button>
            ))}
          </div>

          {visibleResults.length === 0 ? (
            <div style={{ textAlign: 'center', color: '#9ca3af', padding: '40px 0', fontSize: '14px' }}>
              該当するイベントが見つかりませんでした
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              {visibleResults.map((event, index) => (
                <a
                  key={`${event.site}-${event.url}-${index}`}
                  href={event.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ display: 'flex', gap: '12px', padding: '12px 14px', borderRadius: '10px', border: '1px solid #e5e7eb', background: '#fff', textDecoration: 'none', color: 'inherit', alignItems: 'flex-start' }}
                >
                  {event.imageUrl && (
                    <img
                      src={event.imageUrl}
                      alt=""
                      style={{ width: '96px', height: '64px', objectFit: 'cover', borderRadius: '6px', flexShrink: 0 }}
                      onError={(e) => { e.currentTarget.style.display = 'none'; }}
                    />
                  )}
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap', marginBottom: '4px' }}>
                      <span style={{ padding: '1px 8px', borderRadius: '999px', background: siteMeta[event.site]?.color || '#6b7280', color: '#fff', fontSize: '11px', fontWeight: 600 }}>
                        {event.siteLabel}
                      </span>
                      {event.datetimeText && (
                        <span style={{ fontSize: '12px', color: '#374151', fontWeight: 600 }}>📅 {event.datetimeText}</span>
                      )}
                    </div>
                    <div style={{ fontSize: '14px', fontWeight: 600, color: '#111827', marginBottom: '4px', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {event.title}
                    </div>
                    <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', fontSize: '12px', color: '#6b7280' }}>
                      {event.venue && <span>📍 {event.venue}</span>}
                      {event.organizer && <span>👤 {event.organizer}</span>}
                      {event.participants != null && (
                        <span>👥 {event.participants}{event.capacity ? `/${event.capacity}` : ''}人</span>
                      )}
                    </div>
                  </div>
                </a>
              ))}
            </div>
          )}
        </>
      )}

      {results === null && !searching && (
        <div style={{ textAlign: 'center', color: '#9ca3af', padding: '60px 0', fontSize: '14px' }}>
          キーワードを入力して「一斉検索」を押すと、選択したサイトを横断してイベントを探します
        </div>
      )}
    </div>
  );
}
