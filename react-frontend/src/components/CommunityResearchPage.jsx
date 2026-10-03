import { useState } from 'react';
import { searchCommunities } from '../api.js';
import SiteSelectBox from './research/SiteSelectBox.jsx';
import CommunityCard from './research/CommunityCard.jsx';
import { LOCATIONS } from './research/locations.js';

// バックエンド Research::Community 系サービスのキーと対応
const SITES = [
  { key: 'jimoty_member', label: 'ジモティー メンバー募集', color: '#16a085' },
  { key: 'dmm_salon', label: 'DMMオンラインサロン', color: '#e60012' },
  { key: 'campfire', label: 'CAMPFIREコミュニティ', color: '#e5603b' },
  { key: 'meetup_group', label: 'Meetup グループ', color: '#f64060' },
  { key: 'rinri', label: '倫理法人会', color: '#1e5aa8' },
  { key: 'yeg', label: '商工会議所青年部', color: '#0a6b3d' },
];

const ALL_SITE_KEYS = SITES.map((site) => site.key);

const PRESET_KEYWORD_GROUPS = [
  { label: '経営者系', keywords: ['経営者', '起業家', '社長', 'ビジネス', '副業', 'AI', 'マーケティング'] },
  { label: '出会い・サークル系', keywords: ['出会い', '社会人サークル', '飲み会', '友達作り', '恋活'] },
];

export default function CommunityResearchPage({ showToast }) {
  const [keyword, setKeyword] = useState('');
  const [selectedSites, setSelectedSites] = useState(ALL_SITE_KEYS);
  const [selectedLocations, setSelectedLocations] = useState([]); // 空 = 全国
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState(null); // null=未検索
  const [siteErrors, setSiteErrors] = useState({});
  const [countsBySite, setCountsBySite] = useState({});
  const [siteFilter, setSiteFilter] = useState('all');

  function toggleLocation(locationKey) {
    setSelectedLocations((previous) =>
      previous.includes(locationKey)
        ? previous.filter((selectedKey) => selectedKey !== locationKey)
        : [...previous, locationKey]
    );
  }

  // 定番キーワードは state 更新を待たずに検索したいので、キーワードは override で受け取る。
  async function handleSearch(keywordOverride) {
    const trimmedKeyword = (keywordOverride ?? keyword).trim();
    if (!trimmedKeyword) {
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
      const data = await searchCommunities({ keyword: trimmedKeyword, sites: selectedSites, locations: selectedLocations });
      const errors = data.errors || {};
      const communities = data.results || [];
      setResults(communities);
      setSiteErrors(errors);
      setCountsBySite(data.countsBySite || {});
      const errorCount = Object.keys(errors).length;
      if (errorCount > 0) {
        showToast(`${errorCount}サイトで検索に失敗しました（他サイトの結果は表示中）`, 'error');
      } else {
        showToast(`${communities.length}件見つかりました`, 'success');
      }
    } catch (error) {
      showToast(error.message, 'error');
    } finally {
      setSearching(false);
    }
  }

  const siteMeta = Object.fromEntries(SITES.map((site) => [site.key, site]));
  const visibleResults = (results || []).filter(
    (community) => siteFilter === 'all' || community.site === siteFilter
  );

  return (
    <div className="community-page">
      {/* 検索条件 */}
      <div style={{ borderRadius: '12px', border: '1.5px solid #e2d9f3', background: '#faf8ff', padding: '16px', marginBottom: '16px' }}>
        <div className="research-page-header" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px', marginBottom: '8px' }}>
          <div style={{ fontSize: '13px', fontWeight: 600, color: '#5b21b6' }}>
            🏢 コミュニティ検索 — 経営者・サークルを複数サイトから探す
          </div>
        </div>

        <div className="research-search-row" style={{ display: 'flex', gap: '8px', marginBottom: '10px' }}>
          <input
            type="text"
            value={keyword}
            onChange={(event) => setKeyword(event.target.value)}
            onKeyDown={(event) => { if (event.key === 'Enter' && !searching) handleSearch(); }}
            placeholder="例: 経営者"
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

        {PRESET_KEYWORD_GROUPS.map((group) => (
          <div key={group.label} style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', alignItems: 'center', marginBottom: '8px' }}>
            <span style={{ fontSize: '12px', color: '#6b7280', minWidth: '104px' }}>{group.label}:</span>
            {group.keywords.map((preset) => (
              <button
                key={preset}
                type="button"
                className="community-chip"
                disabled={searching}
                onClick={() => { setKeyword(preset); handleSearch(preset); }}
                style={{ padding: '4px 10px', borderRadius: '999px', border: '1px solid #c4b5fd', background: keyword === preset ? '#ede9fe' : '#fff', color: '#6d28d9', fontSize: '12px', cursor: 'pointer' }}
              >
                {preset}
              </button>
            ))}
          </div>
        ))}

        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center', marginBottom: '10px' }}>
          <span style={{ fontSize: '12px', color: '#6b7280' }}>検索先:</span>
          <SiteSelectBox
            sites={SITES}
            selectedKeys={selectedSites}
            onChange={setSelectedSites}
            disabled={searching}
          />
          {selectedSites.length === 0 && (
            <span style={{ fontSize: '11px', color: '#dc2626' }}>1つ以上選んでください</span>
          )}
        </div>

        <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', alignItems: 'center' }}>
          <span style={{ fontSize: '12px', color: '#6b7280' }}>場所:</span>
          {LOCATIONS.map((location) => {
            const selected = selectedLocations.includes(location.key);
            return (
              <button
                key={location.key}
                type="button"
                className="community-chip"
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
        {selectedLocations.length > 0 && (
          <div className="community-hint">
            ※ DMM・CAMPFIRE は地域で絞れません。Meetup・倫理法人会・商工会議所青年部・ジモティーは選択した地域で絞り込みます
          </div>
        )}
      </div>

      {/* サイト別エラー表示 */}
      {Object.keys(siteErrors).length > 0 && (
        <div style={{ borderRadius: '8px', border: '1px solid #fecaca', background: '#fef2f2', padding: '10px 14px', marginBottom: '12px', fontSize: '12px', color: '#b91c1c', overflowWrap: 'anywhere' }}>
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
              className="community-chip"
              onClick={() => setSiteFilter('all')}
              style={{ padding: '3px 10px', borderRadius: '999px', border: '1px solid #d1d5db', background: siteFilter === 'all' ? '#374151' : '#fff', color: siteFilter === 'all' ? '#fff' : '#374151', fontSize: '12px', cursor: 'pointer' }}
            >
              すべて
            </button>
            {SITES.filter((site) => countsBySite[site.key] !== undefined).map((site) => (
              <button
                key={site.key}
                type="button"
                className="community-chip"
                onClick={() => setSiteFilter(site.key)}
                style={{ padding: '3px 10px', borderRadius: '999px', border: `1px solid ${site.color}`, background: siteFilter === site.key ? site.color : '#fff', color: siteFilter === site.key ? '#fff' : site.color, fontSize: '12px', cursor: 'pointer' }}
              >
                {site.label} {countsBySite[site.key]}
              </button>
            ))}
          </div>

          {visibleResults.length === 0 ? (
            <div style={{ textAlign: 'center', color: '#9ca3af', padding: '40px 0', fontSize: '14px' }}>
              該当するコミュニティが見つかりませんでした
            </div>
          ) : (
            <div className="community-list">
              {visibleResults.map((community, index) => (
                <CommunityCard
                  key={`${community.site}-${community.url}-${index}`}
                  community={community}
                  badgeColor={siteMeta[community.site]?.color}
                />
              ))}
            </div>
          )}
        </>
      )}

      {results === null && !searching && (
        <div style={{ textAlign: 'center', color: '#9ca3af', padding: '60px 0', fontSize: '14px' }}>
          キーワードを入力して「一斉検索」を押すと、コミュニティ・サークル・団体を横断して探します
        </div>
      )}
    </div>
  );
}
