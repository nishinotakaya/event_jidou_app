import { google } from "googleapis";
import path from "path";

const KEY = "/Users/nishinotakaya/5.オンクラス自動化/config/keys/google_service_account.json";
const PRESENTATION_ID = "13zjKEO4zTy3tTyE0s_6WSSIyPazsdX89K8COgyREW8w";

const NAVY = { red: 0.043, green: 0.063, blue: 0.125 };
const NAVY2 = { red: 0.067, green: 0.10, blue: 0.208 };
const FG = { red: 0.96, green: 0.97, blue: 1.0 };
const SUB = { red: 0.66, green: 0.70, blue: 0.84 };
const ACCENT = { red: 1.0, green: 0.82, blue: 0.40 };
const ACCENT2 = { red: 0.024, green: 0.84, blue: 0.627 };
const GOLD_BG = { red: 1.0, green: 0.82, blue: 0.40 };
const DARK_TEXT = { red: 0.10, green: 0.10, blue: 0.10 };

const slides = [
  {
    bg: NAVY,
    blocks: [
      { x: 60, y: 120, w: 840, h: 200, text: "今の働き方に\n不安を感じていませんか？", size: 44, bold: true, color: FG, align: "CENTER" },
      { x: 60, y: 340, w: 840, h: 60, text: "— 新しい一歩を、一緒に。 —", size: 20, color: SUB, align: "CENTER" },
    ],
  },
  {
    bg: NAVY,
    blocks: [
      { x: 60, y: 40, w: 840, h: 60, text: "こんな悩み、ありませんか？", size: 32, bold: true, color: FG },
      { x: 60, y: 130, w: 840, h: 360, text: "・ 将来の収入が不安\n・ スキルが足りない気がする\n・ 転職が怖いと感じる\n・ 今の職場に満足できない\n・ 仕事にやりがいを感じない", size: 22, color: FG, lineSpacing: 180 },
    ],
  },
  {
    bg: NAVY,
    blocks: [
      { x: 60, y: 40, w: 840, h: 60, text: "放置すると、こんなリスクが…", size: 32, bold: true, color: FG },
      { x: 60, y: 130, w: 840, h: 360, text: "✅ 収入が減少する可能性\n✅ 職場環境が悪化する\n✅ スキルが陳腐化する\n✅ 自信を失うことがある", size: 24, color: FG, lineSpacing: 180 },
    ],
  },
  {
    bg: NAVY,
    blocks: [
      { x: 60, y: 30, w: 840, h: 50, text: "仕組みを知ろう", size: 16, bold: true, color: ACCENT },
      { x: 60, y: 80, w: 840, h: 70, text: "アプリは「上流 → 下流」で動いている", size: 30, bold: true, color: FG },
      { x: 60, y: 180, w: 260, h: 140, text: "上流\n企画・設計", size: 22, bold: true, color: ACCENT, align: "CENTER", border: ACCENT, fill: NAVY2 },
      { x: 340, y: 220, w: 60, h: 60, text: "→", size: 28, color: SUB, align: "CENTER" },
      { x: 410, y: 180, w: 220, h: 140, text: "バックエンド\nサーバー・DB", size: 20, bold: true, color: FG, align: "CENTER", border: SUB, fill: NAVY2 },
      { x: 650, y: 220, w: 60, h: 60, text: "→", size: 28, color: SUB, align: "CENTER" },
      { x: 720, y: 180, w: 220, h: 140, text: "フロントエンド\n画面・UI", size: 20, bold: true, color: ACCENT2, align: "CENTER", border: ACCENT2, fill: NAVY2 },
      { x: 60, y: 360, w: 840, h: 80, text: "まずは「下流（フロントエンド）」から始めるのが近道。", size: 22, color: SUB, align: "CENTER" },
    ],
  },
  {
    bg: NAVY,
    blocks: [
      { x: 60, y: 40, w: 840, h: 60, text: "「アプリを作る」仕事って？", size: 32, bold: true, color: FG },
      { x: 60, y: 130, w: 840, h: 90, text: "みんなが毎日使っている、あの便利なサービス。\nすべて誰かが「フロントエンド × バックエンド」で作っています。", size: 18, color: FG },
      { x: 60, y: 250, w: 160, h: 60, text: "💬 LINE", size: 20, bold: true, color: FG, align: "CENTER", fill: NAVY2 },
      { x: 235, y: 250, w: 160, h: 60, text: "📷 Instagram", size: 20, bold: true, color: FG, align: "CENTER", fill: NAVY2 },
      { x: 410, y: 250, w: 160, h: 60, text: "🛒 Amazon", size: 20, bold: true, color: FG, align: "CENTER", fill: NAVY2 },
      { x: 585, y: 250, w: 160, h: 60, text: "🎬 YouTube", size: 20, bold: true, color: FG, align: "CENTER", fill: NAVY2 },
      { x: 760, y: 250, w: 140, h: 60, text: "🚕 Uber", size: 20, bold: true, color: FG, align: "CENTER", fill: NAVY2 },
      { x: 60, y: 360, w: 840, h: 60, text: "あなたが「作る側」になれたら？", size: 22, color: ACCENT, align: "CENTER", bold: true },
    ],
  },
  {
    bg: NAVY,
    blocks: [
      { x: 60, y: 40, w: 840, h: 60, text: "このセミナーで得られること", size: 32, bold: true, color: FG },
      { x: 60, y: 130, w: 410, h: 150, text: "📌 安定収入\n稼げる職種・働き方の選択肢を知る", size: 18, color: FG, fill: NAVY2 },
      { x: 490, y: 130, w: 410, h: 150, text: "📌 必要スキル\n下流から始める学習ロードマップ", size: 18, color: FG, fill: NAVY2 },
      { x: 60, y: 300, w: 410, h: 150, text: "📌 不安の解消\n転職の進め方とリアルな実例", size: 18, color: FG, fill: NAVY2 },
      { x: 490, y: 300, w: 410, h: 150, text: "📌 仕組みの理解\n上流→下流／フロント↔バック", size: 18, color: FG, fill: NAVY2 },
    ],
  },
  {
    bg: GOLD_BG,
    blocks: [
      { x: 60, y: 80, w: 840, h: 140, text: "新しい働き方を\n見つけるチャンス。", size: 44, bold: true, color: DARK_TEXT, align: "CENTER" },
      { x: 60, y: 250, w: 840, h: 40, text: "日時：2026年4月15日（水） 20:30 〜 21:30", size: 20, bold: true, color: DARK_TEXT, align: "CENTER" },
      { x: 60, y: 290, w: 840, h: 40, text: "対象：プログラミングに興味がある方 / 初学者の方", size: 18, color: DARK_TEXT, align: "CENTER" },
      { x: 60, y: 320, w: 840, h: 40, text: "形式：オンライン開催", size: 18, color: DARK_TEXT, align: "CENTER" },
      { x: 280, y: 400, w: 400, h: 70, text: "👉 お申し込みはこちら", size: 24, bold: true, color: FG, align: "CENTER", fill: NAVY },
    ],
  },
];

const auth = new google.auth.GoogleAuth({
  keyFile: KEY,
  scopes: ["https://www.googleapis.com/auth/presentations"],
});
const slidesApi = google.slides({ version: "v1", auth: await auth.getClient() });

const pres = await slidesApi.presentations.get({ presentationId: PRESENTATION_ID });
const existingIds = pres.data.slides.map((s) => s.objectId);
console.log(`existing slides: ${existingIds.length}`);

const deleteReqs = existingIds.slice(1).map((id) => ({ deleteObject: { objectId: id } }));
if (deleteReqs.length) {
  await slidesApi.presentations.batchUpdate({
    presentationId: PRESENTATION_ID,
    requestBody: { requests: deleteReqs },
  });
  console.log(`deleted ${deleteReqs.length} slides`);
}

const firstSlideId = existingIds[0];
const createReqs = [];
for (let i = 0; i < slides.length; i++) {
  const slideId = `s_${i}_${Date.now()}`;
  if (i === 0) continue;
  createReqs.push({
    createSlide: {
      objectId: `s_${i}_${Date.now()}`,
      insertionIndex: i,
      slideLayoutReference: { predefinedLayout: "BLANK" },
    },
  });
}
const createRes = await slidesApi.presentations.batchUpdate({
  presentationId: PRESENTATION_ID,
  requestBody: { requests: createReqs },
});
const newSlideIds = createRes.data.replies.filter((r) => r.createSlide).map((r) => r.createSlide.objectId);
const slideIds = [firstSlideId, ...newSlideIds];
console.log(`slide ids: ${slideIds.length}`);

const reqs = [];
slideIds.forEach((sid, i) => {
  const def = slides[i];
  reqs.push({
    updatePageProperties: {
      objectId: sid,
      pageProperties: {
        pageBackgroundFill: { solidFill: { color: { rgbColor: def.bg } } },
      },
      fields: "pageBackgroundFill.solidFill.color",
    },
  });
  def.blocks.forEach((b, j) => {
    const tid = `t_${i}_${j}_${Date.now()}`;
    reqs.push({
      createShape: {
        objectId: tid,
        shapeType: "TEXT_BOX",
        elementProperties: {
          pageObjectId: sid,
          size: { width: { magnitude: b.w, unit: "PT" }, height: { magnitude: b.h, unit: "PT" } },
          transform: { scaleX: 1, scaleY: 1, translateX: b.x, translateY: b.y, unit: "PT" },
        },
      },
    });
    if (b.fill) {
      reqs.push({
        updateShapeProperties: {
          objectId: tid,
          shapeProperties: {
            shapeBackgroundFill: { solidFill: { color: { rgbColor: b.fill } } },
            ...(b.border ? { outline: { outlineFill: { solidFill: { color: { rgbColor: b.border } } }, weight: { magnitude: 2, unit: "PT" } } } : {}),
          },
          fields: b.border ? "shapeBackgroundFill.solidFill.color,outline" : "shapeBackgroundFill.solidFill.color",
        },
      });
    } else if (b.border) {
      reqs.push({
        updateShapeProperties: {
          objectId: tid,
          shapeProperties: { outline: { outlineFill: { solidFill: { color: { rgbColor: b.border } } }, weight: { magnitude: 2, unit: "PT" } } },
          fields: "outline",
        },
      });
    }
    reqs.push({ insertText: { objectId: tid, text: b.text } });
    reqs.push({
      updateTextStyle: {
        objectId: tid,
        textRange: { type: "ALL" },
        style: {
          fontSize: { magnitude: b.size, unit: "PT" },
          bold: !!b.bold,
          foregroundColor: { opaqueColor: { rgbColor: b.color } },
        },
        fields: "fontSize,bold,foregroundColor",
      },
    });
    if (b.align) {
      reqs.push({
        updateParagraphStyle: {
          objectId: tid,
          textRange: { type: "ALL" },
          style: { alignment: b.align },
          fields: "alignment",
        },
      });
    }
  });
});

await slidesApi.presentations.batchUpdate({
  presentationId: PRESENTATION_ID,
  requestBody: { requests: reqs },
});

console.log(`✅ uploaded ${slides.length} slides`);
console.log(`https://docs.google.com/presentation/d/${PRESENTATION_ID}/edit`);
