// satori 用テンプレート群。
// satori は React 要素ライクな {type, props} ツリーを受け取る。JSX を使わず軽量 h() で組む。
// CSS は flexbox のみ（satori 制約）。grid・float などは不可。

export const h = (type, props = {}, ...children) => ({
  type,
  props: { ...props, children: children.length <= 1 ? children[0] : children },
});

// 文字数に応じてフォントサイズを段階で決める（簡易オートフィット）。
// 日本語はコピー長のブレが大きく、固定サイズだと見切れ/スカスカになるため。
function fitFontSize(text, { max, min, longAt }) {
  const len = [...(text || '')].length;
  if (len <= longAt) return max;
  const ratio = Math.min(1, longAt / len);
  return Math.max(min, Math.round(max * ratio));
}

// 共通: ブランド署名フッター
function brandFooter(theme, brand) {
  return h('div', {
    style: {
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      marginTop: 'auto', paddingTop: 28,
    },
  },
    h('div', { style: { display: 'flex', flexDirection: 'column' } },
      h('div', { style: { fontSize: 30, fontWeight: 700, color: theme.fg } }, brand.name),
      h('div', { style: { fontSize: 26, color: theme.sub } }, brand.handle),
    ),
    h('div', {
      style: {
        width: 64, height: 64, borderRadius: 999, background: theme.accent,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 34, fontWeight: 700, color: theme.bg,
      },
    }, '✦'),
  );
}

// 単発カード: 1 メッセージ + 大きな余白。X 1 枚 / IG 単発の主力。
export function singleCard({ title, kicker, theme, tokens }) {
  const titleSize = fitFontSize(title, { max: 84, min: 48, longAt: 26 });
  return h('div', {
    style: {
      width: '100%', height: '100%', display: 'flex', flexDirection: 'column',
      background: theme.bg, color: theme.fg, padding: tokens.pad,
      fontFamily: 'NotoSansJP-Regular',
    },
  },
    kicker && h('div', {
      style: {
        alignSelf: 'flex-start', display: 'flex',
        background: theme.bg2, color: theme.sub, fontSize: 28, fontWeight: 700,
        padding: '12px 22px', borderRadius: 999, marginBottom: 36,
      },
    }, kicker),
    h('div', {
      style: {
        display: 'flex', fontFamily: 'NotoSansJP-Bold', fontWeight: 700,
        fontSize: titleSize, lineHeight: 1.28, letterSpacing: -1,
        // accent の縦ライン
        borderLeft: `10px solid ${theme.accent}`, paddingLeft: 32,
      },
    }, title),
    brandFooter(theme, tokens.brand),
  );
}

// カルーセル表紙: フックで「続きが気になる」を作る。
export function carouselCover({ title, page = '01', theme, tokens }) {
  const titleSize = fitFontSize(title, { max: 92, min: 52, longAt: 22 });
  return h('div', {
    style: {
      width: '100%', height: '100%', display: 'flex', flexDirection: 'column',
      background: theme.bg, color: theme.fg, padding: tokens.pad,
      fontFamily: 'NotoSansJP-Regular',
    },
  },
    h('div', { style: { display: 'flex', justifyContent: 'space-between', fontSize: 28, color: theme.sub } },
      h('div', { style: { display: 'flex' } }, tokens.brand.name),
      h('div', { style: { display: 'flex' } }, `${page} / —`),
    ),
    h('div', {
      style: {
        display: 'flex', flexDirection: 'column', marginTop: 'auto',
        fontFamily: 'NotoSansJP-Bold', fontWeight: 700, fontSize: titleSize,
        lineHeight: 1.22, letterSpacing: -1.5,
      },
    }, title),
    h('div', {
      style: {
        display: 'flex', alignSelf: 'flex-start', marginTop: 40,
        background: theme.accent, color: theme.bg, fontSize: 30, fontWeight: 700,
        padding: '14px 28px', borderRadius: 999,
      },
    }, 'スワイプして見る →'),
  );
}

export const TEMPLATES = { singleCard, carouselCover };
