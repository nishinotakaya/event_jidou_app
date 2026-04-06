# マルチユーザー・メンバー管理機能

## 概要

管理者がメンバーを招待し、イベント・受講生サポートを共有。接続サービスの追加は管理者のみ。各ユーザーは自分のメール/パスワードで各サービスに接続し、投稿は自分のアカウントで実行。

## ユーザーロール

| ロール | 説明 | 初期ユーザー |
|--------|------|-------------|
| **admin（管理者）** | 全機能 + ユーザー管理 + 接続サービス追加 | takaya314boxing@gmail.com |
| **editor（投稿者）** | イベント閲覧・編集・投稿 + 自分の接続情報入力 | proaka_post@gmail.com |
| **viewer（閲覧者）** | イベント閲覧のみ | proaka_event@gmail.com |

## 権限マトリクス

| 機能 | admin | editor | viewer |
|------|-------|--------|--------|
| イベント閲覧 | ✅ | ✅ | ✅ |
| イベント編集・作成 | ✅ | ✅ | ❌ |
| イベント投稿（各サイトへ） | ✅ | ✅（自分の接続で） | ❌ |
| 受講生サポート閲覧 | ✅ | ✅ | ✅ |
| 受講生サポート編集・投稿 | ✅ | ✅ | ❌ |
| **接続サービス追加・削除** | ✅ | ❌ | ❌ |
| **自分の接続情報（メアド/PW）入力** | ✅ | ✅ | ❌ |
| Googleカレンダー | ✅（自分のGoogle） | ✅（Googleログイン時） | ❌ |
| Zoom作成 | ✅ | ✅ | ❌ |
| AI文章生成 | ✅ | ✅ | ✅ |
| ユーザー管理・招待 | ✅ | ❌ | ❌ |
| 受講生一覧 | ✅ | ✅ | ✅ |

## 接続管理の方針

### 管理者（admin）
- **接続サービスの追加・削除**（connpass, Peatix, TechPlay等のサービス自体の追加/削除）
- 自分のメール/パスワードで接続
- 接続テスト・セッション管理

### 投稿者（editor）
- サービスの追加・削除は**不可**
- 管理者が追加したサービス一覧が表示される
- **自分のメール/パスワード**を各サービスに入力して接続
- 投稿時は**自分の接続情報**で各サイトにログイン・投稿
- 接続テスト可能

### 閲覧者（viewer）
- 接続管理にアクセス不可

### 投稿フロー
1. admin が接続サービス（connpass等）を追加
2. editor が自分のメール/パスワードを各サービスに入力
3. editor が投稿ボタンを押すと、**editorの接続情報**で各サイトにログイン・投稿
4. admin が投稿すると、**adminの接続情報**で投稿

## データモデル変更

### usersテーブル追加カラム

```ruby
add_column :users, :role, :string, default: 'viewer', null: false
add_column :users, :invited_by_id, :integer
add_column :users, :invitation_token, :string
add_column :users, :invitation_sent_at, :datetime
add_column :users, :invitation_accepted_at, :datetime
```

### service_connectionsの扱い
- 既存の user_id カラムで各ユーザーの接続を管理（変更なし）
- admin がサービスを追加 → 他ユーザーにもサービス一覧として表示
- 各ユーザーが自分のメール/パスワードを入力 → 自分のServiceConnectionレコードが作成

### available_servicesテーブル（新規）
管理者が追加したサービスのマスター一覧

```ruby
create_table :available_services do |t|
  t.string :service_name, null: false  # 'connpass', 'peatix' etc
  t.boolean :enabled, default: true
  t.references :created_by, foreign_key: { to_table: :users }
  t.timestamps
end
```

## 実装ステップ

### Step 1: DBマイグレーション + 初期データ
- usersにrole等カラム追加
- available_servicesテーブル作成
- takaya314boxing@gmail.com → role: 'admin'
- proaka_post@gmail.com → role: 'editor', password: 'password'
- proaka_event@gmail.com → role: 'viewer', password: 'password'

### Step 2: ユーザー管理API（admin専用）
- `GET /api/admin/users` — ユーザー一覧
- `POST /api/admin/users/invite` — 招待メール送信（email + role）
- `PUT /api/admin/users/:id` — ロール変更
- `DELETE /api/admin/users/:id` — ユーザー削除

### Step 3: 接続管理の権限分離
- サービス追加・削除: admin のみ
- メール/パスワード入力・接続テスト: admin + editor
- 接続一覧: admin は全ユーザーの接続を確認可能、editor は自分のみ

### Step 4: 投稿時のユーザー切り替え
- PostJob に current_user_id を渡す
- ServiceConnection.where(user_id: current_user_id) で接続取得
- セッション復元も current_user のものを使用

### Step 5: 権限チェック（コントローラ）
- `authorize_admin!` — admin専用
- `authorize_editor!` — editor以上
- テキストAPI: 全ロール閲覧可、editor以上で編集
- 接続管理: サービス追加はadmin、メアド/PW入力はeditor以上

### Step 6: フロントエンド
- ユーザー管理ページ（admin専用タブ）
  - ユーザー一覧テーブル
  - 招待フォーム（メール + ロール）
  - ロール変更
- 接続管理画面のロール対応
  - admin: サービス追加ボタン表示
  - editor: メール/パスワード入力のみ
  - viewer: 非表示
- ナビゲーション: roleに応じたメニュー表示

### Step 7: 招待メール
- ActionMailerでGmail API経由
- メール本文: 招待リンク + アプリURL + ロール説明

## 初期データ

```ruby
# 管理者
User.find_by(email: 'takaya314boxing@gmail.com').update!(role: 'admin')

# 投稿者
User.create!(
  email: 'proaka_post@gmail.com',
  password: 'password',
  password_confirmation: 'password',
  name: 'ProAka投稿者',
  role: 'editor',
  invited_by_id: 1
)

# 閲覧者
User.create!(
  email: 'proaka_event@gmail.com',
  password: 'password',
  password_confirmation: 'password',
  name: 'ProAkaイベント',
  role: 'viewer',
  invited_by_id: 1
)
```

## UI表示例

### 接続管理画面（editor視点）
```
🔗 接続管理

connpass    [メール: ________] [パスワード: ________] [テスト] [保存]
Peatix      [メール: ________] [パスワード: ________] [テスト] [保存]
TechPlay    [メール: ________] [パスワード: ________] [テスト] [保存]
...
※ サービスの追加・削除は管理者のみ
```

### ユーザー管理画面（admin視点）
```
👥 ユーザー管理

| 名前 | メール | ロール | 最終ログイン | 操作 |
|------|--------|--------|------------|------|
| 西野鷹也 | takaya314boxing@gmail.com | admin | 2026/04/06 | - |
| ProAka投稿者 | proaka_post@gmail.com | editor ▼ | 未ログイン | 削除 |
| ProAkaイベント | proaka_event@gmail.com | viewer ▼ | 未ログイン | 削除 |

[+ メンバー招待]
```
