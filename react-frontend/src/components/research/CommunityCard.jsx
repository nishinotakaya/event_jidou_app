import { useState } from 'react';

function hasText(value) {
  return typeof value === 'string' ? value.trim() !== '' : Boolean(value);
}

const HTTP_URL_PATTERN = /^https?:\/\//i;

function isHttpUrl(value) {
  return typeof value === 'string' && HTTP_URL_PATTERN.test(value.trim());
}

function hasMemberCount(memberCount) {
  return Number.isFinite(memberCount) || hasText(memberCount);
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
  const linkUrl = isHttpUrl(url) ? url.trim() : null;
  const CardElement = linkUrl ? 'a' : 'div';
  const cardLinkProps = linkUrl ? { href: linkUrl, target: '_blank', rel: 'noopener noreferrer' } : {};
  const showThumbnail = isHttpUrl(imageUrl) && !thumbnailBroken;
  const hasFee = hasText(fee);
  const showMemberCount = hasMemberCount(memberCount);
  const hasOrganizer = hasText(organizer);

  return (
    <CardElement className="community-card" {...cardLinkProps}>
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
        {(hasFee || showMemberCount || hasOrganizer) && (
          <div className="community-card-facts">
            {hasFee && <span>💴 {formatFee(fee)}</span>}
            {showMemberCount && <span>👥 {formatMemberCount(memberCount)}</span>}
            {hasOrganizer && (
              <span className="community-card-organizer" title={organizer}>👤 主宰: {organizer}</span>
            )}
          </div>
        )}
        {hasText(description) && <p className="community-card-desc">{description}</p>}
        {linkUrl && <span className="community-card-link">サイトで見る ↗</span>}
      </div>
    </CardElement>
  );
}
