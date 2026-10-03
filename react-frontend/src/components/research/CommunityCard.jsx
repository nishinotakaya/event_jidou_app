import { useState } from 'react';

function hasText(value) {
  return typeof value === 'string' ? value.trim() !== '' : Boolean(value);
}

function formatMemberCount(memberCount) {
  if (typeof memberCount === 'number') return `${memberCount.toLocaleString('ja-JP')}人`;
  const text = String(memberCount).trim();
  return text.endsWith('人') ? text : `${text}人`;
}

function formatFee(fee) {
  return typeof fee === 'number' ? `${fee.toLocaleString('ja-JP')}円` : String(fee).trim();
}

function hostnameOf(url) {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}

// コミュニティ検索の結果カード。欠損した値は要素ごと出さない（「-」などの埋め文字は使わない）。
export default function CommunityCard({ community, badgeColor }) {
  const [thumbnailBroken, setThumbnailBroken] = useState(false);
  const { url, imageUrl, siteLabel, area, fee, memberCount, organizer, description } = community;
  const name = hasText(community.name) ? community.name : hostnameOf(url);
  const showThumbnail = hasText(imageUrl) && !thumbnailBroken;
  const hasFee = hasText(fee);
  const hasMemberCount = hasText(memberCount);
  const hasOrganizer = hasText(organizer);

  return (
    <a className="community-card" href={url} target="_blank" rel="noopener noreferrer">
      {showThumbnail && (
        <div className="community-card-thumb">
          <img src={imageUrl} alt="" loading="lazy" onError={() => setThumbnailBroken(true)} />
        </div>
      )}
      <div className="community-card-body">
        <div className="community-card-meta">
          <span className="community-badge" style={{ background: badgeColor || '#6b7280' }}>{siteLabel}</span>
          {hasText(area) && <span className="community-area">📍 {area}</span>}
        </div>
        <h3 className="community-card-name">{name}</h3>
        {(hasFee || hasMemberCount || hasOrganizer) && (
          <div className="community-card-facts">
            {hasFee && <span>💴 {formatFee(fee)}</span>}
            {hasMemberCount && <span>👥 {formatMemberCount(memberCount)}</span>}
            {hasOrganizer && (
              <span className="community-card-organizer" title={organizer}>👤 主宰: {organizer}</span>
            )}
          </div>
        )}
        {hasText(description) && <p className="community-card-desc">{description}</p>}
        <span className="community-card-link">サイトで見る ↗</span>
      </div>
    </a>
  );
}
