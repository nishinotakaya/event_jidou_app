# データベース接続情報

## 開発環境（ローカル / Docker）

### MySQL

| 項目 | 値 |
|------|-----|
| ホスト | `127.0.0.1` |
| ポート | `3009` |
| ユーザー名 | `root` |
| パスワード | `password` |
| データベース名 | `myapp_development` |

### Redis（ActionCable / Sidekiq用）

| 項目 | 値 |
|------|-----|
| ホスト | `127.0.0.1`（Docker: `redis`） |
| ポート | `6379` |
| URL | `redis://localhost:6379/1` |

### ローカルサーバー

| サービス | URL |
|----------|-----|
| Rails API | http://localhost:3001 |
| React Frontend | http://localhost:5173 |

---

## 本番環境（Heroku）

### MySQL（JawsDB）

| 項目 | 値 |
|------|-----|
| サービス | JawsDB MySQL (Kitefin / 無料) |
| ホスト | `x71wqc4m22j8e3ql.cbetxkdyhwsb.us-east-1.rds.amazonaws.com` |
| ポート | `3306` |
| データベース名 | `ai0rsio3nha6d39i` |
| ユーザー名 | `ziylmpzl572lbn2k` |
| パスワード | `l9og93l4o3wd0h73` |
| 接続URL | `mysql://ziylmpzl572lbn2k:l9og93l4o3wd0h73@x71wqc4m22j8e3ql.cbetxkdyhwsb.us-east-1.rds.amazonaws.com:3306/ai0rsio3nha6d39i` |

### デプロイ先

| サービス | URL |
|----------|-----|
| バックエンド (Heroku) | https://announcement-d656a48fc066.herokuapp.com/ |
| フロントエンド (Vercel) | https://event-kokuthi-app-front.vercel.app/ |

---

## DB容量（本番 JawsDB）

| 項目 | 値 |
|------|-----|
| プラン上限 | 5 MB |
| 現在の使用量 | 0.28 MB (5.6%) |
| 残り | 4.72 MB |

---

## サービス接続一覧（service_connections）

全サービス共通メールアドレス: `takaya314boxing@gmail.com`

| サービス | メールアドレス | パスワード |
|----------|---------------|-----------|
| connpass | takaya314boxing@gmail.com | Takaya314! |
| kokuchpro | takaya314boxing@gmail.com | Takaya314! |
| peatix | takaya314boxing@gmail.com | Takaya314! |
| techplay | takaya314boxing@gmail.com | Takaya314!!! |
| doorkeeper | takaya314boxing@gmail.com | Takaya314! |
| zoom | takaya314boxing@gmail.com | Takaya314 |
| tunagate | takaya314boxing@gmail.com | (Googleログイン) |
| github | github | (Personal Access Token - .env参照) |
| onclass | takaya314boxing@gmail.com | takaya314 |
| gmail | takaya314boxing@gmail.com | (Googleログイン連携) |
| twitter | takaya314boxing@gmail.com | - |
| instagram | takaya314boxing@gmail.com | - |
| street_academy | takaya314boxing@gmail.com | - |
| eventregist | takaya314boxing@gmail.com | - |
| everevo | takaya314boxing@gmail.com | - |
| luma | takaya314boxing@gmail.com | - |
| seminar_biz | takaya314boxing@gmail.com | - |
| jimoty | takaya314boxing@gmail.com | - |

※ パスワードはDBでは暗号化保存（ENCRYPTION_KEY使用）。上記は.envファイルの値。
※ タイムゾーン: 全環境 `Asia/Tokyo` (TZ=Asia/Tokyo)
