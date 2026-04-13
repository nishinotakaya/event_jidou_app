---
name: jimoty
description: ジモティー投稿自動化 — Rails form POST。Googleログイン必須、イベント作成はPOST /articles
---

# ジモティー（jmty.jp）投稿自動化スキル

## 概要

地域の掲示板サービス。Playwright方式で自動投稿。

## API仕様（解析済み・API化可能）

- **方式**: Rails HTMLフォームPOST（`application/x-www-form-urlencoded`）
- **認証**: Googleログイン → Cookie（`_session_id` + `remember_user_token`）
- **CSRFトークン**: `<meta name="csrf-token">` / `authenticity_token`
- **サービスファイル**: `app/services/posting/jimoty_service.rb`

## イベント作成API

```
POST https://jmty.jp/articles
Content-Type: application/x-www-form-urlencoded

authenticity_token=<CSRF>
category_group_id=2                  # イベント
article[category_id]=22             # セミナー
prefecture_id[1]=12                 # 千葉県
city_id[1]=225                      # 松戸市
article[title]=タイトル
article[text]=本文
article[date]=2026/05/14            # 開催日
article[end_date]=2026/05/14
article[deadline]=2026/05/13        # 募集期限
article[address]=オンライン
```

## 削除

```
DELETE https://jmty.jp/{prefecture}/{category}/article_{id}/destroy
```

注意: 閲覧URLは`article-{id}`（ハイフン）、削除URLは`article_{id}`（アンダースコア）。

## 現状

Playwright方式で稼働中。Net::HTTP化は可能だがGoogleログインのCookie管理が必要。

## 本番: ✅ 稼働中
