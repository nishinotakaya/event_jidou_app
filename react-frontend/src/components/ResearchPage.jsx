import { useState, useEffect } from 'react';
import {
  searchCrossSiteEvents,
  searchViaBrowserFallback,
  fetchResearchFavorites,
  addResearchFavorite,
  removeResearchFavorite,
} from '../api.js';

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

// ワンタップで投げられる定番キーワード。
// 上段＝人脈づくり（経営者交流会・飲み会系）、下段＝AIプログラミングスクールの同業/競合リサーチ用。
const PRESET_KEYWORDS = [
  '経営者 交流会',
  '異業種交流会',
  'ビジネス交流会',
  '起業家 交流会',
  '経営者 朝活',
  '名刺交換会',
  'AI プログラミングスクール',
  'プログラミングスクール',
  '生成AI 勉強会',
  'AI 活用 セミナー',
  'エンジニア 転職 相談会',
];

// ===== 開催日ユーティリティ =====
// 終了したイベントはサーバー側で常に落とされるので、ここで作る範囲は必ず今日以降になる。
function formatDate(date) {
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

function addDays(date, days) {
  const moved = new Date(date);
  moved.setDate(moved.getDate() + days);
  return moved;
}

// ワンタップで開催日を絞るプリセット。交流会は「今週末」「来月」で探されることが多い。
function buildDatePresets(today) {
  const dayOfWeek = today.getDay(); // 0=日曜
  // 今週末＝直近の土曜〜日曜。日曜日に見ているときは土曜が過ぎているので今日だけを指す。
  const saturday = dayOfWeek === 0 ? today : addDays(today, 6 - dayOfWeek);
  const sunday = dayOfWeek === 0 ? today : addDays(saturday, 1);
  const endOfThisMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0);
  const startOfNextMonth = new Date(today.getFullYear(), today.getMonth() + 1, 1);
  const endOfNextMonth = new Date(today.getFullYear(), today.getMonth() + 2, 0);

  return [
    { label: '今日', from: formatDate(today), to: formatDate(today) },
    { label: '今週末', from: formatDate(saturday), to: formatDate(sunday) },
    { label: '今月', from: formatDate(today), to: formatDate(endOfThisMonth) },
    { label: '来月', from: formatDate(startOfNextMonth), to: formatDate(endOfNextMonth) },
    { label: '3ヶ月以内', from: formatDate(today), to: formatDate(addDays(today, 90)) },
  ];
}

const DATE_INPUT_STYLE = {
  padding: '3px 8px', borderRadius: '8px', border: '1px solid #d1d5db', fontSize: '12px', color: '#1f2937',
};

// 検索結果とお気に入り一覧で同じ見た目にしたいので、カードは1箇所で持つ。
// 星ボタンはリンク（<a>）の中に入れず兄弟にしている（入れ子にすると星クリックでもサイトが開いてしまう）。
function EventCard({ event, siteMeta, favorited, onToggleFavorite }) {
  return (
    <div style={{ display: 'flex', gap: '8px', padding: '12px 14px', borderRadius: '10px', border: '1px solid #e5e7eb', background: '#fff', alignItems: 'flex-start' }}>
      <a
        href={event.url}
        target="_blank"
        rel="noopener noreferrer"
        style={{ display: 'flex', gap: '12px', flex: 1, minWidth: 0, textDecoration: 'none', color: 'inherit', alignItems: 'flex-start' }}
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
      <button
        type="button"
        onClick={() => onToggleFavorite(event)}
        title={favorited ? 'お気に入りから外す' : 'お気に入りに追加'}
        aria-label={favorited ? 'お気に入りから外す' : 'お気に入りに追加'}
        aria-pressed={favorited}
        style={{ border: 'none', background: 'transparent', cursor: 'pointer', fontSize: '20px', lineHeight: 1, padding: '2px 4px', color: favorited ? '#f59e0b' : '#d1d5db', flexShrink: 0 }}
      >
        {favorited ? '★' : '☆'}
      </button>
    </div>
  );
}

export default function ResearchPage({ showToast }) {
  const [keyword, setKeyword] = useState('経営者 交流会');
  const [selectedSites, setSelectedSites] = useState(SITES.map((s) => s.key));
  const [selectedLocations, setSelectedLocations] = useState([]); // 空 = 全国
  const [dateFrom, setDateFrom] = useState(''); // 'YYYY-MM-DD' / 空 = 今日以降すべて
  const [dateTo, setDateTo] = useState('');
  const [appliedRange, setAppliedRange] = useState(null); // 実際に検索に使われた範囲（サーバーの返答）
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState(null); // null=未検索
  const [siteErrors, setSiteErrors] = useState({});
  const [countsBySite, setCountsBySite] = useState({});
  const [siteFilter, setSiteFilter] = useState('all'); // 結果一覧の絞り込み
  const [favorites, setFavorites] = useState([]); // 星を付けたイベント（サーバー保存）
  const [showFavorites, setShowFavorites] = useState(false); // true = お気に入りだけを表示

  // 星の付き外しは検索前から見えていてほしいので、ページを開いた時点で読む。
  useEffect(() => {
    fetchResearchFavorites()
      .then(setFavorites)
      .catch((err) => showToast(err.message, 'error'));
  }, [showToast]);

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

  // プリセット（キーワード・開催日）は state 更新を待たずに検索したいので、
  // 検索条件は overrides で受け取れるようにしている。
  async function handleSearch(overrides = {}) {
    const trimmed = (overrides.keyword ?? keyword).trim();
    const from = overrides.dateFrom ?? dateFrom;
    const to = overrides.dateTo ?? dateTo;
    if (!trimmed) {
      showToast('キーワードを入力してください', 'error');
      return;
    }
    if (selectedSites.length === 0) {
      showToast('検索するサイトを1つ以上選択してください', 'error');
      return;
    }
    if (from && to && to < from) {
      showToast('開催日の終了日は開始日以降にしてください', 'error');
      return;
    }
    setSearching(true);
    setSiteFilter('all');
    try {
      const data = await searchCrossSiteEvents({ keyword: trimmed, sites: selectedSites, locations: selectedLocations, dateFrom: from, dateTo: to });
      const { results: mergedResults, errors, counts } = await retryBlockedSitesFromBrowser(data, { dateFrom: from, dateTo: to });
      setResults(mergedResults);
      setSiteErrors(errors);
      setCountsBySite(counts);
      setAppliedRange({ from: data.searchedDateFrom, to: data.searchedDateTo });
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

  // Peatix のようにサーバー（Heroku）のIPを弾くサイトを、ブラウザ（＝自分の回線）から取り直して合流させる。
  // サーバーが「取り直せるサイト」と判断したものだけが data.browserFallbacks に入ってくるので、
  // ここではサイト名を一切ハードコードしない。取り直しに成功したらそのサイトのエラー表示は消し、
  // 失敗したら元のエラーに理由を足して残す（黙って消すとユーザーが取りこぼしに気付けない）。
  async function retryBlockedSitesFromBrowser(data, { dateFrom: from, dateTo: to }) {
    const errors = { ...(data.errors || {}) };
    const counts = { ...(data.countsBySite || {}) };
    const fallbackEntries = Object.entries(data.browserFallbacks || {});

    const retried = await Promise.all(
      fallbackEntries.map(async ([site, fallback]) => {
        try {
          const siteResults = await searchViaBrowserFallback({ site, fallback, locations: selectedLocations, dateFrom: from, dateTo: to });
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

  const favoriteUrls = new Set(favorites.map((favorite) => favorite.url));

  // 星は連打されるので、先に画面を更新してから通信する（失敗したら元に戻して知らせる）。
  async function toggleFavorite(event) {
    const wasFavorited = favoriteUrls.has(event.url);
    const previousFavorites = favorites;
    setFavorites(wasFavorited
      ? favorites.filter((favorite) => favorite.url !== event.url)
      : [ ...favorites, event ]);
    try {
      if (wasFavorited) {
        await removeResearchFavorite(event.url);
      } else {
        await addResearchFavorite(event);
      }
    } catch (err) {
      setFavorites(previousFavorites);
      showToast(err.message, 'error');
    }
  }

  const todayText = formatDate(new Date());
  const datePresets = buildDatePresets(new Date());
  const dateRangeSummary = appliedRange
    ? `📅 ${appliedRange.from} 〜 ${appliedRange.to || '指定なし'}（終了したイベントは非表示）`
    : null;

  function applyDatePreset(preset) {
    const cleared = dateFrom === preset.from && dateTo === preset.to;
    const from = cleared ? '' : preset.from;
    const to = cleared ? '' : preset.to;
    setDateFrom(from);
    setDateTo(to);
    if (results !== null) handleSearch({ dateFrom: from, dateTo: to });
  }

  const siteMeta = Object.fromEntries(SITES.map((s) => [s.key, s]));
  const visibleResults = (results || []).filter(
    (r) => siteFilter === 'all' || r.site === siteFilter
  );

  return (
    <div style={{ padding: '0 24px 24px' }}>
      {/* 検索条件 */}
      <div style={{ borderRadius: '12px', border: '1.5px solid #e2d9f3', background: '#faf8ff', padding: '16px', marginBottom: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px', marginBottom: '8px' }}>
          <div style={{ fontSize: '13px', fontWeight: 600, color: '#5b21b6' }}>
            🔎 交流会リサーチ — 複数サイトを一斉検索
          </div>
          <button
            type="button"
            onClick={() => setShowFavorites((shown) => !shown)}
            style={{ padding: '3px 12px', borderRadius: '999px', border: '1px solid #fcd34d', background: showFavorites ? '#f59e0b' : '#fff', color: showFavorites ? '#fff' : '#b45309', fontSize: '12px', fontWeight: 600, cursor: 'pointer' }}
          >
            {showFavorites ? '★ お気に入り表示中' : `☆ お気に入り ${favorites.length}`}
          </button>
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
              onClick={() => { setKeyword(preset); handleSearch({ keyword: preset }); }}
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

        {/* 開催日（未指定 = 今日以降すべて。開催日が過ぎたイベントは常に非表示） */}
        <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', alignItems: 'center', marginTop: '10px' }}>
          <span style={{ fontSize: '12px', color: '#6b7280' }}>開催日:</span>
          <input
            type="date"
            value={dateFrom}
            min={todayText}
            onChange={(e) => setDateFrom(e.target.value)}
            style={DATE_INPUT_STYLE}
          />
          <span style={{ fontSize: '12px', color: '#9ca3af' }}>〜</span>
          <input
            type="date"
            value={dateTo}
            min={dateFrom || todayText}
            onChange={(e) => setDateTo(e.target.value)}
            style={DATE_INPUT_STYLE}
          />
          {datePresets.map((preset) => {
            const selected = dateFrom === preset.from && dateTo === preset.to;
            return (
              <button
                key={preset.label}
                type="button"
                disabled={searching}
                onClick={() => applyDatePreset(preset)}
                style={{ padding: '3px 10px', borderRadius: '999px', border: '1px solid #93c5fd', background: selected ? '#2563eb' : '#fff', color: selected ? '#fff' : '#1d4ed8', fontSize: '12px', fontWeight: selected ? 600 : 400, cursor: 'pointer' }}
              >
                {preset.label}
              </button>
            );
          })}
          {(dateFrom || dateTo) ? (
            <button
              type="button"
              onClick={() => { setDateFrom(''); setDateTo(''); if (results !== null) handleSearch({ dateFrom: '', dateTo: '' }); }}
              style={{ padding: '3px 10px', borderRadius: '999px', border: '1px solid #d1d5db', background: '#fff', color: '#6b7280', fontSize: '12px', cursor: 'pointer' }}
            >
              指定なし
            </button>
          ) : (
            <span style={{ fontSize: '11px', color: '#9ca3af' }}>（未指定 = 今日以降すべて／終了したイベントは表示しません）</span>
          )}
        </div>
        {(dateFrom || dateTo) && (
          <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '6px' }}>
            ※ サイト側で日付を絞れない検索先（Peatix・TechPlay など）は直近の検索結果から絞り込むため、先の日付ほど件数が少なくなります
          </div>
        )}
      </div>

      {/* サイト別エラー表示 */}
      {Object.keys(siteErrors).length > 0 && (
        <div style={{ borderRadius: '8px', border: '1px solid #fecaca', background: '#fef2f2', padding: '10px 14px', marginBottom: '12px', fontSize: '12px', color: '#b91c1c' }}>
          {Object.entries(siteErrors).map(([siteKey, message]) => (
            <div key={siteKey}>⚠️ {siteMeta[siteKey]?.label || siteKey}: {message}</div>
          ))}
        </div>
      )}

      {/* お気に入り一覧（検索していなくても見られる） */}
      {showFavorites && (
        <>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '10px' }}>
            <span style={{ fontSize: '13px', fontWeight: 600, color: '#374151' }}>
              ★ お気に入り {favorites.length}件
            </span>
            <button
              type="button"
              onClick={() => setShowFavorites(false)}
              style={{ padding: '3px 10px', borderRadius: '999px', border: '1px solid #d1d5db', background: '#fff', color: '#6b7280', fontSize: '12px', cursor: 'pointer' }}
            >
              検索結果に戻る
            </button>
          </div>

          {favorites.length === 0 ? (
            <div style={{ textAlign: 'center', color: '#9ca3af', padding: '40px 0', fontSize: '14px' }}>
              検索結果の ☆ を押すと、ここに貯まります
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              {favorites.map((event) => (
                <EventCard
                  key={`favorite-${event.url}`}
                  event={event}
                  siteMeta={siteMeta}
                  favorited
                  onToggleFavorite={toggleFavorite}
                />
              ))}
            </div>
          )}
        </>
      )}

      {/* 結果一覧 */}
      {!showFavorites && results !== null && (
        <>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap', marginBottom: '10px' }}>
            <span style={{ fontSize: '13px', fontWeight: 600, color: '#374151' }}>
              検索結果 {results.length}件
            </span>
            {dateRangeSummary && (
              <span style={{ fontSize: '12px', color: '#6b7280' }}>{dateRangeSummary}</span>
            )}
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
                <EventCard
                  key={`${event.site}-${event.url}-${index}`}
                  event={event}
                  siteMeta={siteMeta}
                  favorited={favoriteUrls.has(event.url)}
                  onToggleFavorite={toggleFavorite}
                />
              ))}
            </div>
          )}
        </>
      )}

      {!showFavorites && results === null && !searching && (
        <div style={{ textAlign: 'center', color: '#9ca3af', padding: '60px 0', fontSize: '14px' }}>
          キーワードを入力して「一斉検索」を押すと、選択したサイトを横断してイベントを探します
        </div>
      )}
    </div>
  );
}
