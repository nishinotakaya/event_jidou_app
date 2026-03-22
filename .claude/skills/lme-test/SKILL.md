---
name: lme-test
description: LME（エルメ）への投稿テスト。体験会・勉強会それぞれのテスト送信とログ確認。
user-invocable: true
---

# LME 投稿テスト

Rails バックエンドが `localhost:3001` で起動していること。

---

## 体験会テスト（taiken）

```bash
curl -s -X POST http://localhost:3001/api/post \
  -H "Content-Type: application/json" \
  -d '{
    "content": "【テスト】オンライン体験会\n\nプログラミングに興味ある方、ぜひご参加ください！",
    "sites": ["LME:taiken"],
    "eventFields": {
      "title": "オンライン体験会テスト",
      "eventDate": "2026-04-01",
      "lmeSendDate": "2026-04-01",
      "lmeSendTime": "10:00",
      "lmeAccount": "taiken",
      "zoomUrl": "https://us02web.zoom.us/j/84192949741?pwd=test123",
      "zoomId": "841 9294 9741",
      "zoomPasscode": "470487"
    },
    "generateImage": false
  }'
```

レスポンス例: `{"job_id":"xxxxxxxxxxxxxxxx"}`

---

## 勉強会テスト（benkyokai）

```bash
curl -s -X POST http://localhost:3001/api/post \
  -H "Content-Type: application/json" \
  -d '{
    "content": "【テスト】業務効率化勉強会\n\n受講生向け勉強会のお知らせです。",
    "sites": ["LME:benkyokai"],
    "eventFields": {
      "title": "業務効率化勉強会テスト",
      "eventDate": "2026-04-01",
      "lmeSendDate": "2026-04-01",
      "lmeSendTime": "20:30",
      "lmeAccount": "benkyokai",
      "zoomUrl": "https://us02web.zoom.us/j/86043831989?pwd=test456",
      "zoomId": "860 4383 1989",
      "zoomPasscode": "123456"
    },
    "generateImage": false
  }'
```

---

## ログ確認

```bash
# Rails開発ログをリアルタイム確認
tail -f rails-backend/log/development.log | grep -E "LME|broadcast_id|エラー|save-group|create-message"
```

### 正常系のログ確認ポイント

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

---

## 作成されたブロードキャストの確認

ログに表示される URL を開く:
```
https://step.lme.jp/basic/add-broadcast-v2?broadcast_id=XXXXXXX
```

### チェック項目
- [ ] テキストメッセージが入っているか
- [ ] ボタンパネルが入っているか
- [ ] パネルタイトル = イベントタイトルか
- [ ] 「参加する」クリック → Zoom URLメッセージ + タグ付与
- [ ] 「参加しない」クリック → フォローメッセージ
- [ ] タグ名 = `M月D日 参加予定`（開催日）か
- [ ] 配信日時が正しいか

---

## よくあるエラーと対処

| エラー | 原因 | 対処 |
|--------|------|------|
| `2captcha タイムアウト` | reCAPTCHA解決サービスが遅延 | 再実行（外部サービスの問題） |
| `new_group_id=nil` | save-groupのレスポンス解析失敗 | `redirect_url`パース処理を確認 |
| `タグIDが取得できません` | タグリスト取得失敗 | `find_tag_items_from_responses` のログを確認 |
| `テンプレート保存失敗` | group_idが不正 | save-groupの戻り値を確認 |
