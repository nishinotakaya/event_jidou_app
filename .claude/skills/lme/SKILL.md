---
name: lme
description: LME（エルメ）投稿自動化 — reCAPTCHAログイン・テンプレート作成・タグ管理・ブロードキャスト配信・フィルタ設定の全フロー
---

# LME（エルメ）投稿自動化スキル

## 概要

LME（step.lme.jp）へのイベント告知ブロードキャスト自動作成。reCAPTCHA対応ログイン → アカウント選択 → テンプレート作成（タグ・アクション・パネル） → ブロードキャスト下書き作成 → フィルタ設定まで一貫処理。

## 現在のステータス

**一時停止中**（post_job.rb line 93-94）
理由: 配信ユーザー絞り込み調整中

## アカウント種別

| アカウント | lmeAccount | 用途 |
|---|---|---|
| 体験会 | `taiken` | プログラミング無料体験会の告知 |
| 勉強会 | `benkyokai` | 受講生向け勉強会の告知 |

## 投稿フロー

```
1. ログイン（https://step.lme.jp）
   - メール: #email_login, input[name="email"]
   - パスワード: #password_login, input[name="password"]
   - reCAPTCHA: 2captcha API で自動解決
   - button[type="submit"] クリック
   - セッション Cookie（laravel_session / XSRF-TOKEN）で認証確認

2. アカウント選択（プロアカ）
   - /admin/home に遷移
   - XPathで「プロアカ」AND「体験会」or「勉強会」を含む要素をクリック
   - 新しいタブが開く → context.waitForEvent('page')

3. テンプレート作成（体験会の場合）
   a. テンプレートグループ作成: POST /ajax/template-v2/save-group
   b. タグ作成/検索: "M月D日 参加予定" 形式
   c. アクション保存: POST /ajax/action/save（タグ付与設定）
   d. テンプレート保存: POST /ajax/template-v2/save-template

4. ブロードキャスト作成
   - POST /ajax/save-broadcast-v2（下書き）
   - フィルタ設定: POST /ajax/filter/save-filter-v2
   - テンプレート適用: POST /ajax/broadcast/create-message-by-template

5. 完了 → broadcast_id をログ出力
```

## reCAPTCHA 解決フロー（2captcha）

```
1. ページ上の data-sitekey を取得
2. POST http://2captcha.com/in.php
   - method: userrecaptcha
   - googlekey: <sitekey>
   - pageurl: <current URL>
3. 20秒待機
4. GET http://2captcha.com/res.php でポーリング
   - 最大24回 × 5秒間隔（合計2分）
5. 取得したトークンを #g-recaptcha-response に注入
6. change イベントを dispatch
```

## CSRFトークン

```javascript
// XSRF-TOKEN Cookie から取得
const rawCookie = document.cookie.split(';')
  .find(c => c.trim().startsWith('XSRF-TOKEN='));
const csrfToken = decodeURIComponent(rawCookie.split('=').slice(1).join('='));
```

全APIリクエストに以下ヘッダーを付与:
```
X-CSRF-TOKEN: <token>
X-Requested-With: XMLHttpRequest
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

## APIエンドポイント一覧

### プロフィール・概要
| メソッド | パス | 用途 |
|---|---|---|
| POST | `/ajax/broadcast/init-list-bots-profiles` | プロフィール一覧取得 |
| GET | `/basic/static-overview` | アクティブフレンド数取得 |

### タグ管理
| メソッド | パス | 用途 |
|---|---|---|
| POST | `/ajax/get-list-group-tag` | タグリスト取得 |
| POST | `/ajax/save-add-tag-in-modal-action` | タグ新規作成 |

### テンプレート管理
| メソッド | パス | 用途 |
|---|---|---|
| POST | `/ajax/template-v2/save-group` | テンプレートグループ作成 |
| POST | `/ajax/template-v2/save-template` | テンプレート保存 |
| GET | `/basic/park-template/list-template/{group_id}` | テンプレート確認 |

### ブロードキャスト管理
| メソッド | パス | 用途 |
|---|---|---|
| POST | `/ajax/save-broadcast-v2` | ブロードキャスト作成/更新 |
| POST | `/ajax/get-detail-broadcast-v2` | ブロードキャスト詳細取得 |
| POST | `/ajax/broadcast/create-message-by-template` | テンプレートからメッセージ作成 |

### フィルタ管理
| メソッド | パス | 用途 |
|---|---|---|
| POST | `/ajax/filter/save-filter-v2` | 配信フィルタ保存 |

### アクション管理
| メソッド | パス | 用途 |
|---|---|---|
| POST | `/ajax/action/save` | アクション保存（タグ付与等） |

## 体験会テンプレートの定数

```ruby
TAIKEN_TAG_GROUP_ID      = '5238317'
TAIKEN_TEMPLATE_GROUP_ID = '14088042'
TAIKEN_TEMPLATE_CHILD_ID = '14088044'
TAIKEN_MSG_TEMPLATE_ID   = '14088038'
TAIKEN_PARK_TEMPLATE_ID  = '14088102'
TAIKEN_PANEL_ID          = 1857170
TAIKEN_TEMPLATE_ID       = 14088044
TAIKEN_ACTION_ID_SANKA   = '20049679'  # 「参加する」アクション
TAIKEN_ACTION_ID_FUSANKA = '20049680'  # 「参加しない」アクション
```

## タグ名フォーマット

```
"M月D日 参加予定"
例: "4月13日 参加予定"
```

開催日（eventDate / startDate）から自動生成。

## テンプレートデータ構造

```javascript
{
  type: 'text',
  message_text: {
    content: "メッセージ本文（Zoom情報含む）",
    urls: [],
    number_action_url_redirect: 1,
    use_preview_url: 1,
    is_shorten_url: 1
  },
  template_group_id: '-11' or 'GROUP_ID',
  action_type: 'sendAll',
  broadcastId: 'BROADCAST_ID'
}
```

## ブロードキャストパラメータ

```javascript
{
  broadcast_id: "",           // 新規作成時は空
  send_day: "2026-04-13",    // 配信日
  send_time: "10:00",        // 配信時刻
  setting_send_message: "1",
  profile_id: "PROFILE_ID",
  filter_number: "471",      // 配信対象人数
  name: "イベント名",
  status: "draft"            // 下書き
}
```

## フィルタ設定

### 体験会フィルタ
```javascript
[
  {
    type: 'tag',
    tag_condition: 0,  // 含む
    tags_search: [1495570],  // 前回セミナー不参加 & 受講生以外
    list_tags: [{ id: 1495570, name: '前回セミナー不参加 & 受講生以外' }]
  },
  {
    type: 'tag',
    tag_condition: '2',  // 除外
    tags_search: [1478703, 1620158],
    list_tags: [
      { id: 1478703, name: 'プログラミング無料体験したい' },
      { id: 1620158, name: '参加希望 2025-8-20' }
    ]
  }
]
```

### 勉強会フィルタ
- `day_add_friend`: 特定日以降の友達
- タグ: フロントコース（延長サポート）（tag_id: 1092591）

## 環境変数

```
LME_BASE_URL=https://step.lme.jp
LME_EMAIL=xxx@example.com
LME_PASSWORD=xxx
LME_BOT_ID=17106
API2CAPTCHA_KEY=xxx
RECAPTCHA_SITE_KEY=6LdjCMgrAAAAAFWGoDFc97UltzaaNJmQcTNsgAO1
RECAPTCHA_SECRET_KEY=6LdjCMgrAAAAACEYJ6jzHIUcJdk-SxQNgnrh9R9N
```

## eventFields スキーマ

```javascript
{
  title: "イベント名",
  startDate: "2026-04-13",    // or eventDate
  startTime: "10:00",
  lmeAccount: "taiken",       // or "benkyokai"
  lmeSendDate: "2026-04-13",  // 配信日
  lmeSendTime: "10:00",       // 配信時刻
  zoomUrl: "https://zoom.us/j/...",
  zoomId: "841 9294 9741",
  zoomPasscode: "470487"
}
```

## URL構築パターン

```javascript
const ts = Date.now();
const botIdUrl = `?botIdCurrent=${encodeURIComponent(BOT_ID)}&isOtherBot=1&_ts=${ts}`;
```

## 関連ファイル

- `rails-backend/app/services/posting/lme_service.rb` - 投稿サービス本体（1000行超）
- `rails-backend/app/jobs/post_job.rb` - PostJob から呼出（現在コメントアウト）
- `api/lme.js` - Node.js版（614行、参考用）
- `scripts/test-lme-post.js` - テストスクリプト
- `scripts/capture-lme-broadcast.js` - API呼び出しキャプチャ

## データフロー

```
[ログイン] reCAPTCHA解決 → セッション取得
  ↓
[アカウント選択] 体験会 or 勉強会
  ↓
[テンプレート作成] タグ作成 → アクション設定 → テンプレート保存
  ↓
[ブロードキャスト] 下書き作成 → フィルタ設定 → テンプレート適用
  ↓
[完了] broadcast_id をログ出力（手動で配信確認）
```

## 正常系ログ確認ポイント

```
[LME] ✅ ログイン完了
[LME][体験会テンプレ] save-group: {"success":true,"redirect_url":"...?template_id=XXXXXXX"}
[LME][体験会テンプレ] new_group_id="XXXXXXX"
[LME][体験会テンプレ] タグID: XXXXXXX name=M月D日 参加予定
[LME][体験会テンプレ] アクション保存: {"success":true,"action_id":"20049679"}
[LME][体験会テンプレ] テンプレート保存: {"success":true}
[LME] create-message-by-template: {"success":true}
[LME] ✅ 下書き作成完了 broadcast_id=XXXXXXX
```

## 注意事項

- reCAPTCHA解決に20〜120秒かかる（外部サービス依存）
- アカウント選択時に新しいタブが開く → Playwright の page 参照を切り替える必要あり
- XSRF-TOKEN は URL エンコードされている → decodeURIComponent 必須
- テンプレートのgroup_id は save-group レスポンスの redirect_url から抽出
- フィルタの tag_id はハードコードされている（変更時はコード修正が必要）
