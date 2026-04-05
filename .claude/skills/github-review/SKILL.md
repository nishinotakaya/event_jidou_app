---
name: github-review
description: GitHubレビュー自動化 — オンクラスメンション検知 → ローカルリポジトリ検出/クローン → VS Code起動 → アプリ起動 → コードレビュー → 受講生サポートに起票
---

# GitHubレビュー自動化スキル

## 概要

オンクラスコミュニティのメンションから未対応のGitHub URLを検出し、
ローカルにリポジトリを用意 → VS Code起動 → アプリ起動 → コードレビュー → 受講生サポートに起票する。

## フロー全体像（UIの「🔍 GitHubスキャン」ボタン1つで全自動実行）

```
1. オンクラス「メンション」タブをスキャン（Playwright）
2. 対応済みフレーズ（「お進みください」「LGTM」等）を含むメンションを除外
3. 残った未対応メンションからGitHub URLを検出（https://なしにも対応）
4. ローカルリポジトリ検索/セットアップ
   a. 既にローカルにある → git pull → VS Code で開く → ブラウザ開く
   b. ない → フォルダ作成 → git clone → VS Code で開く → アプリ起動
5. 動作テスト実行（npm test / npm run build / npm run lint）
6. テスト失敗時 → Playwrightでスクリーンショット撮影 → ローカル保存
7. Claude Code CLI (`claude -p`) でコードレビュー（Max契約内・追加費用なし）
8. レビューを REVIEW_*.md としてリポジトリ内に保存
9. スクリーンショットをGitHub Contents APIで自動アップロード
10. 受講生サポートの「Gitレビュー」フォルダに起票（スクリーンショットURL埋め込み）
11. ユーザー確認 → 承認 → GitHubにコメント投稿
```

## 動作テスト

### テスト判定ロジック

| ファイル | テストコマンド |
|---|---|
| `package.json` に `test` スクリプト | `npm test -- --run` |
| `package.json` に `lint` スクリプト | `npm run lint` |
| `package.json` に `build` スクリプト | `npm run build` |
| `Gemfile` | `bundle exec rails test` |
| 上記なし | スキップ（テスト対象なし） |

### スクリーンショット撮影条件

- テスト失敗時に自動撮影
- Playwrightでトップページ + 内部リンク（最大3ページ）+ エラー画面を撮影
- 保存先: `{リポジトリ}/review_screenshots/`
  - `top.png` — トップページ
  - `page_1.png` 〜 `page_3.png` — 内部ページ
  - `errors.png` — コンソールエラー検出時

### GitHubへの画像アップロード

`GITHUB_TOKEN` が設定されている場合、GitHub Contents APIでスクリーンショットを自動コミット：
```
PUT /repos/{owner}/{repo}/contents/review_screenshots/{filename}
```
レビューコメントに `![screenshot](download_url)` で画像を埋め込み。

## レビュー生成方式

**Claude Code CLI** を非対話モード (`claude -p`) で実行。
Max契約に含まれるため追加のAPIキー・費用は不要。

```bash
claude -p --output-format text --max-turns 1 "レビュープロンプト"
```

リポジトリのローカルパス内で実行するため、Claude Codeがコードを直接参照してレビュー可能。

## レビュー観点（必須チェック項目）

Claude Codeがレビューする際、以下の観点を**具体的なファイル名・行番号・コード断片を示して**指摘すること。
「良い」「改善が必要」だけでなく、**現象・原因・対策案**のセットで書く。

### A. データの整合性・競合

- **読み込みと保存の競合**: 非同期読み込み完了前にstate初期値（`[]`等）で保存が走り、データが消えないか
- **useEffectの依存配列**: 画面遷移後にデータが再取得されるか（マウント時のみ読み込みで古いデータが残る問題）
- **二重保存**: useEffectでの自動保存と、ハンドラ内での手動保存（setTimeout等）が重複していないか
- **ID採番の衝突**: `Math.max(...ids)` など表示中データだけからIDを採番していないか。UUID推奨
- **型安全でないデータ読み込み**: localforage/localStorage等から取得した値を `as Type` でキャストしているが、`Array.isArray` チェックがない

### B. 状態管理

- **制御コンポーネント vs 非制御**: `<select defaultValue>` ではなく `<select value={state}>` を使うべき
- **リロード後のstate復元**: フィルタ・ソート等のUI状態がリロードで消えないか（URLクエリ or localStorage）
- **setStateの非同期性**: `setState` 直後に新しい値を使って保存・計算していないか

### C. バリデーション・エッジケース

- **不正な入力値**: URLクエリ `?date=invalid` や空文字で `Invalid Date` / `NaN` が混ざらないか
- **配列でないデータ**: 古い形式や壊れたデータが入っている場合の `.map is not a function` エラー
- **境界値**: 日付の前月末・翌月初、空配列、undefined

### D. コード品質

- **不要なコード**: `console.log` のデバッグ出力、コメントアウトされた関数ブロック（Git履歴で復元可能）
- **インラインスタイルの整理**: 大量のインラインスタイルがあればCSSクラスに分離
- **コンポーネント分割**: 1ファイル300行以上なら分割を提案（TodoItem, TodoForm, FilterSelect等）
- **型定義の分離**: コンポーネント内の型定義は `types.ts` に切り出す

### E. パフォーマンス

- **不要な再計算**: `useMemo` なしのソート・フィルタ処理が毎レンダリングで走っていないか
- **全キースキャン**: localforage等で毎回全データを読み込んでいないか（インデックス推奨）
- **useCallback/useMemo**: 頻繁にreレンダリングされるコンポーネントで最適化されているか

### F. フレームワーク固有

- **React**: DOM直接操作（`document.querySelector`）よりライブラリのコールバック（`dateClick`等）を使う
- **FullCalendar**: `@fullcalendar/interaction` の `dateClick` を使う（DOM操作で `addEventListener` しない）
- **React Router**: `useLocation` / `useNavigate` で画面遷移を管理

### G. セキュリティ

- **APIキーの露出**: フロントエンドにAPIキーがハードコードされていないか
- **XSS**: ユーザー入力を `dangerouslySetInnerHTML` で描画していないか
- **認証情報**: `.env` がコミットされていないか

### レビュー出力フォーマット

各指摘は以下の形式で書く：

```markdown
## N. 指摘タイトル（端的に）

**現象:** ユーザーから見てどう困るか
**場所:** `ファイルパス` の N〜M 行目
**原因:** なぜそうなるかの技術的説明

**該当コード:**
\`\`\`tsx
// 問題のコード断片
\`\`\`

**対策案:**
\`\`\`tsx
// 修正後のコード例
\`\`\`
```

## ディレクトリ構成

### ベースディレクトリ

```
~/3.フロントコース_カリキュラムチェック/
```

### フォルダ命名規則

```
~/3.フロントコース_カリキュラムチェック/
  ├── 谷藤さん_todo_b/
  │   └── todo_list_B/          ← git clone されたリポジトリ
  │       ├── package.json
  │       └── ...
  ├── 山下さん_Todo_Bレビュー/
  │   └── todo_list_B/
  ├── 青地さんレビュー/
  │   └── portfolio/
  └── 〇〇さん_レビュー/        ← 新規作成時の命名
      └── {repo_name}/
```

### 新規フォルダ命名パターン

GitHubユーザー名 or オンクラスの投稿者名から生成:
- `{名前}さん_{リポジトリ種別}` 例: `田中さん_TodoB`
- 名前が不明な場合: `{GitHubユーザー名}_{リポジトリ名}`

## ローカルリポジトリ検索ロジック

### Step 1: 既存ローカルリポジトリの検索

```bash
# ベースディレクトリ配下の全gitリポジトリのremote URLを取得
find ~/1.フロントコース_カリキュラムチェック -name ".git" -maxdepth 3 -exec dirname {} \; \
  | while read dir; do
      url=$(git -C "$dir" remote get-url origin 2>/dev/null)
      echo "$dir|$url"
    done
```

### Step 2: GitHub URLとローカルパスのマッチング

GitHub URL `https://github.com/user/repo` と一致する `origin` を持つローカルリポジトリを検索。
マッチング時は以下を正規化:
- `.git` サフィックスの有無
- `https://` vs `git@github.com:` 形式

### Step 3: ローカルにある場合

```bash
cd {ローカルパス}
git pull origin main  # or master, develop
code .                # VS Code を開く
```

### Step 4: ローカルにない場合

```bash
# フォルダ作成
mkdir -p ~/3.フロントコース_カリキュラムチェック/{名前}さん_{種別}/
cd ~/3.フロントコース_カリキュラムチェック/{名前}さん_{種別}/

# クローン
git clone {github_url}
cd {repo_name}

# VS Code を開く
code .

# アプリ起動（package.json の有無で判定）
if [ -f package.json ]; then
  npm install
  npm run dev  # or npm start
fi
```

## 対応済み判定フレーズ

以下のフレーズがメンション内（自分の返信含む）に含まれていたら対応済みとしてスキップ:

```
お進みください / 進めてください / 問題なさそう / 問題ありません
修正ありがとう / ありがとうございます / LGTM / lgtm
良さそう / いい感じ / 大丈夫です / OKです / okです
確認しました / レビュー済み / マージして
```

## VS Code 起動コマンド

```bash
code {リポジトリパス}
```

macOS では `/usr/local/bin/code` または `~/.local/bin/code` にシンボリックリンクが必要。
`which code` で確認。なければ:
```bash
# VS Code のコマンドパレット → "Shell Command: Install 'code' command in PATH"
```

## アプリ起動判定

リポジトリ内のファイルからアプリの種類を判定:

| ファイル | 判定 | 起動コマンド |
|---|---|---|
| `package.json` + `vite` in devDependencies | Vite (React/Vue) | `npm install && npm run dev` |
| `package.json` + `react-scripts` | CRA | `npm install && npm start` |
| `package.json` + `next` | Next.js | `npm install && npm run dev` |
| `package.json` のみ | Node.js | `npm install && npm start` |
| `Gemfile` | Rails | `bundle install && rails s` |
| `index.html` のみ | 静的HTML | `open index.html` or Live Server |

## 関連ファイル

### バックエンド（Rails）

| ファイル | 役割 |
|---|---|
| `app/services/onclass_community_scanner.rb` | メンションタブスキャン・GitHub URL検出 |
| `app/services/github_review_service.rb` | GitHub API連携・AIレビュー生成・コメント投稿 |
| `app/jobs/github_review_scan_job.rb` | バッチJob（スキャン→レビュー→起票） |
| `app/controllers/api/github_reviews_controller.rb` | APIエンドポイント |
| `app/models/github_review.rb` | レビュー管理モデル |
| `lib/tasks/github_review.rake` | Rakeタスク (`rails github:scan`) |

### フロントエンド（React）

| ファイル | 役割 |
|---|---|
| `react-frontend/src/api.js` | fetchGithubReviews, approveGithubReview, postGithubComment, scanGithubReviews |
| `react-frontend/src/components/ItemCard.jsx` | Gitレビューフォルダのカードに承認・GitHub投稿ボタン |
| `react-frontend/src/App.jsx` | 「🔍 GitHubスキャン」ボタン（受講生サポートモード時） |

### DB

```
github_reviews テーブル:
  - github_url (unique)
  - github_type: pr / issue / repo / commit
  - repo_full_name: owner/repo
  - pr_number
  - author: コミュニティ投稿者名
  - onclass_post_id
  - item_id: 受講生サポートの item_id
  - status: pending → reviewed → approved → posted
  - review_content
  - github_comment_url: 投稿済みコメントURL
  - images: JSON array
```

## 環境変数

| 変数 | 用途 | 必須 |
|---|---|---|
| `GITHUB_TOKEN` | GitHub API（PR取得・コメント投稿） | GitHubコメント投稿時 |
| `OPENAI_API_KEY` | レビュー生成 | レビュー生成時 |

## 実行方法

### CLI
```bash
npm run github-scan           # Rakeタスク実行
rails github:scan             # 同上（rails-backend内）
rails github:list             # レビュー一覧表示
```

### UI
受講生サポートモード → ヘッダーの「🔍 GitHubスキャン」ボタン

### バッチ（定期実行）
```bash
# crontab -e で設定例（毎時実行）
0 * * * * cd ~/イベント\ 自動告知用/rails-backend && ~/.rbenv/versions/3.1.2/bin/ruby ~/.rbenv/versions/3.1.2/bin/rails github:scan >> /tmp/github-scan.log 2>&1
```
