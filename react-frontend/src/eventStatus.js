// イベントステータス判定ユーティリティ
// 開催日(+終了時刻) を過ぎたら 'ended'、それ以外は 'upcoming'

export function getEventStatus(item) {
  if (!item || !item.eventDate) return 'upcoming';
  const endTime = item.eventEndTime || item.eventTime || '23:59';
  const endStr = `${item.eventDate}T${endTime}:00+09:00`;
  const end = new Date(endStr);
  if (isNaN(end)) return 'upcoming';
  return end.getTime() < Date.now() ? 'ended' : 'upcoming';
}

export function statusLabel(status) {
  return status === 'ended' ? '終了' : '募集中';
}

export function statusMatchesQuery(status, query) {
  if (!query) return true;
  const q = query.trim();
  if (q.includes('終了')) return status === 'ended';
  if (q.includes('募集中') || q.includes('開催前')) return status === 'upcoming';
  return true;
}
