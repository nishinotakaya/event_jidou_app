# 開発フロー・ワークフロールール

タスクを実行する際、以下のワークフローとコア原則に従うこと。

---

## 6ロール体制

開発タスクは以下の6ロールで実行する。メインエージェント（自分）が **PM** として全体を統括する。

```
PM (メインエージェント)  ── 要件定義・技術設計・影響分析・進行管理・意思決定
  │
  ├─ 1. Plan        ← PM: 要件定義・技術設計・インターフェース定義・規約抽出
  ├─ 2. Assess      ← PM: 影響範囲分析
  ├─ 2.5 Design     ← デザイナーサブエージェント (UI変更がある場合のみ)
  │     入力: 要件 + 既存デザインパターン
  │     出力: UI仕様 + モックアップ画像
  │
  ├─ 3. Write Tests ← テストサブエージェント (Task)
  │     入力: 変更仕様 + インターフェース定義 + テスト要件
  │     出力: テスト項目一覧 + テストコード（実装前なので全件 FAIL が正常）
  │
  ├─ 4. Implement   ← 実装サブエージェント (Task, isolation: "worktree")
  │     入力: 計画 + UI仕様 + テストコード + 対象ファイル一覧 + 変更仕様 + 関連規約
  │     出力: worktree ブランチ上のコード変更（テストが通る実装）
  │
  ├─ 5. Test        ← Bash: プロジェクトの品質ゲートスクリプトを実行
  │
  ├─ 6. Review      ← レビューサブエージェント + デザイナーサブエージェント (並列)
  │     コード: diff + /coding-rules → 違反リスト or LGTM
  │     デザイン: スクリーンショット + UI仕様 → 意匠・UX違反リスト or LGTM
  │
  ├─ 7. Fix         ← PM: 修正方針策定 → 実装サブエージェントで修正 → 5(Test)に戻る
  │
  ├─ 8. Merge       ← PM: worktree → develop → main にマージ
  │
  ├─ 9. Deploy & QA ← PM: デプロイ + ヘルスチェック → QAエージェント: E2Eテスト + エビデンス保存 → PM: LINE 完了報告
  │
  └─ 10. Retro      ← PM: 振り返り → lessons.md 更新 → 規約・フロー改善
```

### ブランチ構造

```
main (本番)  ← develop からのマージのみ
  └── develop (開発統合)  ← PM が管理
        ├── feat/xxx  ← 実装サブエージェント (worktree 隔離)
        └── fix/yyy   ← 実装サブエージェント (worktree 隔離)
```

### 各ロールの責務

| ロール | 担当 | 読むべきスキル | やること | やらないこと |
|--------|------|---------------|---------|-------------|
| **PM** | メイン | `/develop`, `/coding-rules` | 要件定義、技術設計、影響分析、規約抽出、ユーザー対話、進行管理、マージ、デプロイ、ヘルスチェック、最終判定、LINE通知、振り返り | コード実装、テスト記述、規約チェック（全件走査）、デザイン作成、E2Eテスト実行 |
| デザイナーエージェント | サブ | `/design-rules` (あれば) | UI仕様策定、モックアップ生成、デザインレビュー | コード実装、コードレビュー |
| 実装エージェント | サブ | (計画から受け取る) | コード変更 | テスト記述、規約チェック、コミット |
| テストエージェント | サブ | (計画から受け取る) | 単体・結合・システムテストの3フェーズでテストコードを徹底的に作り込む | 実装コード変更、規約チェック |
| レビューエージェント | サブ | `/coding-rules` (必須) | 規約準拠チェック、違反箇所の指摘 | コード修正 |
| QAエージェント | サブ | `/DRBFM`, `qa-scenarios.yml` | DRBFM変更点分析、テストシナリオ導出、デプロイ後E2Eテスト実行、スクリーンショット取得、Firebase へのエビデンス保存、テストレポート作成 | コード修正、デプロイ操作、LINE通知 |

### デザイナーエージェントの適用判断

全タスクでデザイナーを起動するわけではない。PM が以下の基準で判断する:

| 変更内容 | デザイナー起動 |
|---------|--------------|
| UI コンポーネントの新規作成 | **必須** |
| 既存 UI のレイアウト・見た目変更 | **必須** |
| API・バックエンドのみの変更 | スキップ |
| テスト・リファクタリングのみ | スキップ |
| テキスト・コピーの変更のみ | 推奨（トーン確認） |

---

## 開発サイクル

### Step 1. Plan — 計画策定（デュアルAIレビュー必須）

1. 要件を理解し、方針・技術設計案を策定する
2. **インターフェース定義**: テストエージェントが先にテストを書けるよう、以下を明確にする
   - ファイルパス（新規・変更対象）
   - クラス名・関数名・メソッドシグネチャ
   - 入出力の型・期待する振る舞い
   - API の場合: エンドポイント・リクエスト/レスポンス形式
3. `/coding-rules` を読み、今回の変更に関連する規約・禁止パターンを抽出する（規約全体ではなく該当部分のみ）
4. **Codex CLI にセカンドオピニオンを求める**（後述「デュアルAI意思決定」参照）
5. Codex の意見を踏まえ、最終方針を確定する
6. 確定した計画を tasks/todo.md に記述する（チェック項目を含む）
7. 重要なタスク（3ステップ以上）は必ずプランモードにする

### Step 2. Assess — 影響範囲分析

計画策定後、コードを書く前に以下を実施する。

1. **変更対象の特定**: どのファイル・クラス・関数を変更するか列挙する
2. **依存関係の調査**: 変更対象を呼び出している箇所、変更対象が呼び出している箇所を洗い出す
3. **影響範囲の判定**: 変更が波及するモジュール、テストを特定する
4. **リスク評価**: 以下を確認する
   - 既存のAPIレスポンス形式が変わらないか
   - 既存テストが壊れないか
   - 外部連携に影響しないか
   - DBスキーマ変更が必要か（マイグレーション）
   - 型定義の互換性が保たれるか
5. **判断**: 他機能に悪影響がある場合は以下のいずれかを選択する
   - **方針変更**: 悪影響を回避できる別のアプローチを採用する
   - **実装中止**: リスクが大きすぎる場合は実装しない。ユーザーに理由を報告する

影響範囲分析の結果は `tasks/todo.md` に記録すること。

### Step 2.5 Design — UI/UX 設計（UI 変更がある場合のみ）

PM が「UI 変更あり」と判断した場合、デザイナーサブエージェントを起動する。

**プロンプトに以下を含めること:**

```
UI/UX 設計を行ってください。

## 要件
<要件の要約>

## 既存デザインパターン
<プロジェクトで使用しているデザインシステム（Tailwind, shadcn/ui 等）、既存の画面構成>

## タスク
1. コンポーネント構成・レイアウト・配色・間隔をテキストで定義する
2. /gen-rich-image スキルでモックアップ画像を生成する
3. 既存デザインシステムとの整合性を確認する

## 出力形式
- UI 仕様（テキスト）: コンポーネント構造、レイアウト、色・間隔・タイポグラフィ
- モックアップ画像: gen-rich-image で生成したもの
- デザインシステム準拠チェック: 違反があれば指摘
```

デザイナーの出力は Step 4 (Implement) の入力に含める。

### Step 3. Write Tests — テスト項目策定 + テストコード記述（TDD）

**実装より先に**テストサブエージェントを起動し、仕様ベースでテストを書かせる。
実装コードの diff ではなく **Step 1 のインターフェース定義と変更仕様** からテストを書くため、実装バイアスがゼロになる。

**プロンプトに以下を含めること:**

```
- 変更仕様 (何を実現するか)
- インターフェース定義 (Step 1 で策定したファイルパス・クラス名・メソッドシグネチャ・入出力)
- 既存テストの構成 (テストフレームワーク、ディレクトリ構造、ヘルパー)
- テスト要件 (下記テスト記述ルール参照)
- worktree のパスとブランチ (PM が事前に作成、または新規作成を指示)
- worktree 上でテストコードをコミットすること
```

#### テスト記述ルール — 3フェーズテスト戦略

テストエージェントは以下の3フェーズで**徹底的に**テストコードを作り込む。
テストの網羅性がプロダクト品質を決定する。テストが甘ければ本番障害に直結する。妥協しない。

##### Phase 1: 単体テスト（Unit Test）

最小単位の関数・メソッド・クラスを隔離してテストする。外部依存はモック/スタブで置換。

| 変更内容 | 必須テスト | カバレッジ目標 |
|---------|----------|-------------|
| ビジネスロジック追加・変更 | 全パブリックメソッドのユニットテスト | 正常系 + 異常系 + 境界値 |
| DB モデル変更 | モデルスペック（バリデーション・スコープ・関連・コールバック） | 全バリデーションルール・全スコープ |
| ユーティリティ関数 | 入出力の全パターン | エッジケース（nil, 空文字, 最大値等）を含む |
| バグ修正 | バグを再現するテスト（修正前に失敗、修正後に成功） | 再発防止のため回帰テストとして残す |

**単体テストで必ず検証する観点:**
- 正常系: 期待通りの入力に対する期待通りの出力
- 異常系: 不正な入力・例外・エラーハンドリング
- 境界値: 0, 1, 最大値, nil/null, 空文字, 空配列
- 副作用: DB書き込み、外部API呼び出し、メール送信等の副作用が正しく発生/抑制されるか

##### Phase 2: 結合テスト（Integration Test）

複数のモジュール・レイヤーを組み合わせた状態でテストする。モジュール間の接合部を重点的に検証。

| 変更内容 | 必須テスト | 検証ポイント |
|---------|----------|------------|
| API エンドポイント追加・変更 | リクエストスペック（正常系 + 異常系 + 認証・認可） | ルーティング → コントローラ → サービス → DB の一連の流れ |
| サービス層の追加・変更 | サービス統合テスト | 複数モデル・外部APIとの連携が正しく動作するか |
| UI コンポーネント追加・変更 | コンポーネント統合テスト（描画 + インタラクション + API連携） | 親子コンポーネント間のデータフロー、状態管理との連携 |
| DB スキーマ変更 | マイグレーション前後のデータ整合性テスト | 既存データが壊れないか、関連テーブルへの影響 |

**結合テストで必ず検証する観点:**
- モジュール間のデータ受け渡しが正しいか（型、フォーマット、null安全性）
- 認証・認可が正しく機能するか（未認証、権限不足、他人のリソースへのアクセス）
- トランザクション境界が正しいか（途中失敗時のロールバック）
- レスポンス形式が API 仕様と一致するか（ステータスコード、ボディ構造、ヘッダー）

##### Phase 3: システムテスト（System Test / E2E Test）

ユーザー視点でシステム全体を通したシナリオをテストする。実環境に近い状態で動作検証。

| 変更内容 | 必須テスト | 検証ポイント |
|---------|----------|------------|
| ユーザーフロー変更 | E2Eシナリオテスト（主要ユースケースの一連の操作） | 画面遷移、データ永続化、表示反映の一貫性 |
| 認証・認可フロー変更 | ログイン〜操作〜ログアウトの一連のフロー | セッション管理、リダイレクト、権限エスカレーション防止 |
| 外部連携変更 | 外部APIとの疎通を含むシナリオ | エラーレスポンス時のフォールバック、リトライ動作 |

**システムテストで必ず検証する観点:**
- ユーザーが実際に行う操作シナリオが正常に完了するか
- エラー発生時にユーザーに適切なフィードバックが返るか
- データの一貫性（作成→表示→更新→削除が正しく反映されるか）

##### テスト不要のケース

- 設定ファイルのみの変更（環境変数、CI 設定等）
- ドキュメント・コメントのみの変更
- CSS/スタイルのみの変更（デザインレビューで担保）

##### フェーズ適用判断マトリクス

変更規模に応じて、テストエージェントは以下を基準にフェーズを適用する:

| 変更規模 | Phase 1 (単体) | Phase 2 (結合) | Phase 3 (システム) |
|---------|:---:|:---:|:---:|
| 関数・メソッド単位の変更 | **必須** | 推奨 | — |
| 複数モジュールにまたがる変更 | **必須** | **必須** | 推奨 |
| ユーザーフロー・画面に影響する変更 | **必須** | **必須** | **必須** |
| バグ修正 | **必須**（再現テスト） | 関連する結合部分 | 関連するフローがあれば |

#### テストエージェントの出力

1. **テスト戦略**: どのフェーズをどの観点で適用するかの方針（PM が確認・承認するため）
2. **テスト項目一覧**: フェーズ別に整理された全テストケース一覧
3. **テストコード**: 実装前なので全件 FAIL が正常。実装後に PASS になることがゴール
4. **カバレッジ見積**: 各フェーズで何をカバーし、何をカバーしないかの明示

### Step 4. Implement — 実装サブエージェントに委譲 (worktree 隔離)

Task ツールで実装サブエージェントを **`isolation: "worktree"`** 付きで起動する。
これによりサブエージェントは隔離された worktree で作業し、develop/main を直接汚さない。

**ゴール: Step 3 で書かれたテストが全件 PASS する実装を書くこと。**

プロンプトに以下を含めること:

```
- 計画の要約 (何を、なぜ変更するか)
- 変更対象ファイルの一覧
- 変更仕様 (具体的な修正内容)
- UI 仕様 + モックアップ (Step 2.5 の出力。UI 変更がある場合)
- テストコード (Step 3 の出力。このテストを通す実装を書くこと)
- 制約事項 (壊してはいけないもの + Step 1 で抽出した関連コーディング規約)
- 実装コードのみ書くこと（テストコードは変更しない）
- worktree 上でコミットすること
```

サブエージェント完了後、worktree のパスとブランチ名が返される。

### Step 5. Test — 品質ゲート実行

プロジェクトの品質ゲートスクリプト（例: `scripts/quality_gate.sh`）を実行する。

失敗した場合:
1. エラー内容を全件分析
2. 実装サブエージェントで一括修正（テストコードは変更しない）
3. 再度品質ゲートを実行
4. 3回失敗したら停止してユーザーに報告

### Step 6. Review — コードレビュー + デザインレビュー

**コードレビューとデザインレビューを並列で起動する。** デザインレビューは UI 変更がある場合のみ。

#### 6a. コードレビュー（レビューサブエージェント）

Task ツールでレビューサブエージェントを起動する。**以下のプロンプトをそのまま使うこと**:

```
コーディング規約に基づくレビューを実施してください。

## 手順
1. まず /coding-rules スキルファイルを読み込む:
   Read <PROJECT_ROOT>/.claude/commands/coding-rules.md
   （プロジェクトローカルに存在しない場合は親ディレクトリの規約を読む）
2. 変更差分を確認する:
   Bash: git -C <PROJECT_ROOT> diff --cached (または git diff HEAD)
3. 差分の各変更について、coding-rules の禁止パターンに違反していないか1項目ずつチェックする
4. コミット前チェックリストの全項目を確認する

## 出力形式
- 違反なし → 「LGTM」とだけ返す
- 違反あり → 以下の形式で全件列挙する:
  [§番号] ファイル:行番号 — 違反内容 — 修正方法

## 追加チェック: 新種の設計懸念
禁止パターンに該当しないが、以下のような設計上の懸念がある箇所があれば NOTE として別途報告する:
- 既存の共通モジュールを使わずに同等のロジックを新規実装している
- 1ファイルの責務が肥大化している（目安: 200行超）
- 新しいライブラリ/パターンの導入が既存の設計方針と一貫していない
- 将来的に禁止パターンに追加すべき新しいアンチパターンの兆候

NOTE は修正必須ではない。PM が判断し、必要なら規約に追加する。
```

#### 6b. デザインレビュー（デザイナーサブエージェント）— UI 変更がある場合のみ

Task ツールでデザイナーサブエージェントを **6a と並列で**起動する。

```
実装結果のデザインレビューを実施してください。

## 手順
1. 実装された画面のスクリーンショットを撮影する（mcp__chrome-devtools__take_screenshot）
2. Step 2.5 で策定した UI 仕様・モックアップと比較する
3. 既存デザインシステムとの整合性を確認する

## チェック項目
- レイアウト: UI 仕様通りの配置・間隔になっているか
- 配色・タイポグラフィ: デザインシステムのトークンを使用しているか
- レスポンシブ: 主要ブレークポイントで崩れていないか
- インタラクション: ホバー・フォーカス・エラー状態が適切か
- アクセシビリティ: コントラスト比、フォーカス順序、aria 属性

## 出力形式
- 問題なし → 「LGTM」とだけ返す
- 問題あり → 以下の形式で全件列挙する:
  [D-連番] 対象要素 — 問題内容 — 修正方法
```

### Step 7. Fix — 違反があれば修正

コードレビュー・デザインレビューで違反が指摘された場合:
1. 違反内容を分析し修正方針を策定する（NOTE の採否判断を含む）
2. 実装サブエージェントで修正（テストコードは原則変更しない）
3. Step 4 (Implement) の worktree 上で修正後、Step 5 (Test) に戻る

### Step 8. Merge — develop → main へマージ

全チェック通過後、worktree ブランチを develop にマージし、続けて main にマージする。

```bash
# worktree → develop
git checkout develop
git merge --no-ff <worktree-branch> -m "Merge <worktree-branch>: <変更の要約>"

# develop → main
git checkout main
git merge --no-ff develop -m "Release: <リリース内容の要約>"
git push origin main
git checkout develop         # 作業ブランチに戻る
```

マージ後、worktree ブランチは自動クリーンアップされる（Task ツールの仕様）。
手動で残っている場合は `git branch -d <branch>` で削除する。

### Step 9. Deploy & QA — デプロイ + 本番QA + エビデンス保存 + 完了報告

main へのマージ後、デプロイ → ヘルスチェック → DRBFM分析 → QAテスト → エビデンス保存 → 完了報告を一連で実施する。

```
9.1 Deploy        ← PM: デプロイ実行
9.2 Health Check  ← PM: ビルドログ・ヘルスチェック確認
9.3 DRBFM + Prep  ← QAエージェント: 変更点分析 → 心配点洗い出し → テストシナリオ導出 + qa-scenarios.yml の smoke シナリオ選定
9.4 QA Execute    ← QAエージェント: DRBFM由来 + 既存シナリオのE2Eテスト + スクリーンショット取得
9.5 Evidence Store← QAエージェント: Firebase Storage + Firestore に保存（DRBFM分析YAMLを含む）
9.6 QA Report     ← QAエージェント → PM: DRBFM分析結果 + テスト結果レポート返却
9.7 Notify        ← PM: LINE Bot で完了報告 or 失敗通知
```

#### 9.1 Deploy — デプロイ実行

プロジェクトのデプロイルール（`/deploy-rules` 等）に従い、デプロイを実行する。

#### 9.2 Health Check — ヘルスチェック

デプロイ完了後、PM が以下を確認する:

1. ビルドログにエラーがないこと
2. デプロイステータスが正常であること
3. ヘルスチェックエンドポイント（あれば）が応答すること

失敗した場合はデプロイをロールバックし、ユーザーに報告する。

#### 9.3 DRBFM + QA Prep — 変更点分析 + テストシナリオ準備

PM がQAエージェントを Task ツールで起動する。QAエージェントは以下を実施する:

1. **DRBFM変更点分析**: `/DRBFM` スキルに従い、git diff から変更点・変化点を抽出し、影響分析マトリクスで心配点を洗い出す
2. **テストシナリオ導出**: 心配点から追加テストシナリオを導出する（DRBFM由来シナリオ）
3. **既存シナリオ選定**: `qa-scenarios.yml` から smoke シナリオ（全デプロイ必須）+ 変更関連の feature シナリオを選定

**既存シナリオの選定基準:**

| カテゴリ | 実行タイミング |
|---------|--------------|
| `smoke` | **全デプロイで必須** |
| `feature` | 変更に関連するシナリオを選定 |
| `regression` | PM 判断（大規模変更・リスクが高い場合） |

#### 9.4–9.6 QA Execute / Evidence Store / QA Report — QAエージェントに委譲

**QAエージェント起動プロンプトテンプレート:**

```
デプロイ後のDRBFM分析 + QAテストを実施してください。

## 前提
まず /DRBFM スキルファイルを読み込んでください:
Read <WORKING_DIR>/

## プロジェクト情報
- プロジェクト名: <project_name>
- 本番URL: <base_url>
- ベースコミット (前回デプロイ): <base_commit>
- デプロイコミット: <deploy_commit>
- デプロイ内容の要約: <deploy_summary>

## Phase 1: DRBFM変更点分析
/DRBFM の「QAエージェントのDRBFM実施プロセス」に従い実施:
1. git diff <base_commit>..<deploy_commit> で変更点・変化点を抽出
2. 影響分析マトリクスを作成
3. 心配点を洗い出し（分析フィルタ6項目を全適用）
4. 心配点からテストシナリオを導出
5. DRBFM分析シート（YAML）を作成

## Phase 2: テスト実行
以下のテストを順次実行:
A. DRBFM由来のテストシナリオ（Phase 1 で導出）
B. 既存テストシナリオ（下記参照）

<qa-scenarios.yml から選定したシナリオをYAML形式で貼付>

各テスト項目ごとに:
1. chrome-devtools MCP でページ遷移・操作を実行
2. 期待結果を確認
3. スクリーンショットを取得 (mcp__chrome-devtools__take_screenshot)
4. pass / fail を判定
5. Firebase Storage にスクリーンショットをアップロード
6. Firestore にテスト結果を記録

## Phase 3: エビデンス保存
- DRBFM分析シート（YAML）を Firebase Storage に保存
- テスト結果を Firestore に保存（drbfm_analysis フィールドを含む）

## Firebase 設定
- GCP プロジェクト: gen-lang-client-0181310850
- Storage バケット: gen-lang-client-0181310850-qa-evidence
- Storage パス: qa-evidence/<project_name>/<YYYY-MM-DD>/<test_run_id>/<order>-<scenario_id>.png
- DRBFM分析パス: qa-evidence/<project_name>/<YYYY-MM-DD>/<test_run_id>/drbfm-analysis.yml
- Firestore コレクション: qa_test_runs

## 出力形式
テスト完了後、以下のレポートを返却:

### DRBFM分析サマリー
- 変更点数 / 心配点数 / 高リスク心配点数
- 導出テストシナリオ数
- 主要な心配点と推奨対応の一覧

### テスト結果サマリー
- テストラン ID
- 総件数 / 合格数 / 失敗数
- 各テスト項目の結果一覧 (scenario_id, name, status, screenshot_url, source: drbfm|existing)
- 失敗項目の詳細 (expected vs actual)
```

**QAエージェントの実行フロー:**

1. `/DRBFM` スキルファイルを読み込む
2. **DRBFM分析**:
   - git diff で変更点・変化点を抽出
   - 影響分析マトリクスを作成
   - 心配点を洗い出し（分析フィルタ6項目を全適用）
   - 心配点からテストシナリオを導出
   - DRBFM分析シート（YAML）を生成
3. テストラン ID を生成（`<project>_<timestamp>` 形式）
4. **DRBFM由来テスト + 既存テストを順次実行**:
   - `navigate`: `mcp__chrome-devtools__navigate_page` でページ遷移
   - `wait_for`: `mcp__chrome-devtools__wait_for` で要素の表示を待機
   - `click` / `fill` 等: 対応する chrome-devtools MCP ツールで操作
   - `screenshot`: `mcp__chrome-devtools__take_screenshot` でスクリーンショット取得
   - 期待結果と実際の結果を比較し pass/fail を判定
5. スクリーンショットを Firebase Storage にアップロード、署名付きURLを取得
6. DRBFM分析シート（YAML）を Firebase Storage にアップロード
7. Firestore にテスト結果ドキュメント + DRBFM分析メタデータを作成
8. 全項目完了後、テストランサマリーを Firestore に保存
9. DRBFM分析結果 + テストレポートを PM に返却

#### テストシナリオ定義ファイル（qa-scenarios.yml）

各プロジェクトルートに `qa-scenarios.yml` を配置する。

```yaml
# 例: OnclassRAG/qa-scenarios.yml
project: OnclassRAG
base_url: https://onclass-rag.onrender.com

scenarios:
  - id: top-page-access
    name: トップページ表示確認
    category: smoke  # smoke | feature | regression
    steps:
      - action: navigate
        url: "{{base_url}}"
      - action: wait_for
        selector: "main"
      - action: screenshot
    expected: "main 要素が表示されていること"

  - id: login-flow
    name: ログインフロー確認
    category: smoke
    steps:
      - action: navigate
        url: "{{base_url}}/login"
      - action: wait_for
        selector: "form"
      - action: fill
        selector: "#email"
        value: "test@example.com"
      - action: fill
        selector: "#password"
        value: "{{env.TEST_PASSWORD}}"
      - action: click
        selector: "button[type='submit']"
      - action: wait_for
        selector: "[data-testid='dashboard']"
      - action: screenshot
    expected: "ダッシュボードが表示されていること"
```

**カテゴリ定義:**
- `smoke`: 基本的な疎通確認。全デプロイで必ず実行
- `feature`: 特定機能の動作確認。変更に関連するシナリオを選定して実行
- `regression`: 回帰テスト。PM判断で大規模変更時に実行

#### Firebase データモデル

**Firestore コレクション設計:**

```
qa_test_runs/{test_run_id}
  ├── project: string              # プロジェクト名
  ├── environment: "production"    # 環境
  ├── deploy_commit: string        # デプロイコミットハッシュ
  ├── deploy_summary: string       # デプロイ内容の要約
  ├── started_at: timestamp        # テスト開始時刻
  ├── completed_at: timestamp      # テスト完了時刻
  ├── total_count: number          # テスト総件数
  ├── pass_count: number           # 合格件数
  ├── fail_count: number           # 失敗件数
  ├── status: "pass" | "fail"      # テストラン全体の結果
  │
  └── results/{result_id}          # サブコレクション
        ├── order: number            # 実行順序
        ├── scenario_id: string      # シナリオID (qa-scenarios.yml の id)
        ├── scenario_name: string    # シナリオ名
        ├── category: string         # smoke | feature | regression
        ├── status: "pass" | "fail" | "error"
        ├── expected: string         # 期待結果
        ├── actual: string           # 実際の結果
        ├── screenshot_url: string   # 署名付きURL
        ├── screenshot_path: string  # Storage 上のパス
        └── executed_at: timestamp   # 実行時刻
```

**Firebase Storage パス設計:**

```
qa-evidence/{project_name}/{YYYY-MM-DD}/{test_run_id}/{order}-{scenario_id}.png
```

バケット: `gen-lang-client-0181310850-qa-evidence` (asia-northeast1)

#### Firebase 操作コードスニペット（QAエージェント用）

**Firebase Admin SDK 初期化（ADC認証）:**

```typescript
import { initializeApp, applicationDefault } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'
import { getStorage } from 'firebase-admin/storage'

const app = initializeApp({
  credential: applicationDefault(),
  storageBucket: 'gen-lang-client-0181310850-qa-evidence',
})

const db = getFirestore(app)
const bucket = getStorage(app).bucket()
```

**Storage: スクリーンショットアップロード + 署名付きURL生成:**

```typescript
import * as fs from 'fs'

async function uploadScreenshot(
  localPath: string,
  storagePath: string
): Promise<{ url: string; path: string }> {
  const file = bucket.file(storagePath)
  await file.save(fs.readFileSync(localPath), {
    contentType: 'image/png',
    metadata: { cacheControl: 'public, max-age=31536000' },
  })

  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: Date.now() + 365 * 24 * 60 * 60 * 1000, // 1年
  })

  return { url, path: storagePath }
}
```

**Firestore: テストラン・結果ドキュメント作成:**

```typescript
import { FieldValue } from 'firebase-admin/firestore'

async function createTestRun(params: {
  testRunId: string
  project: string
  deployCommit: string
  deploySummary: string
}) {
  await db.collection('qa_test_runs').doc(params.testRunId).set({
    project: params.project,
    environment: 'production',
    deploy_commit: params.deployCommit,
    deploy_summary: params.deploySummary,
    started_at: FieldValue.serverTimestamp(),
    completed_at: null,
    total_count: 0,
    pass_count: 0,
    fail_count: 0,
    status: 'pending',
  })
}

async function addTestResult(testRunId: string, result: {
  order: number
  scenarioId: string
  scenarioName: string
  category: string
  status: 'pass' | 'fail' | 'error'
  expected: string
  actual: string
  screenshotUrl: string
  screenshotPath: string
}) {
  await db
    .collection('qa_test_runs')
    .doc(testRunId)
    .collection('results')
    .add({
      order: result.order,
      scenario_id: result.scenarioId,
      scenario_name: result.scenarioName,
      category: result.category,
      status: result.status,
      expected: result.expected,
      actual: result.actual,
      screenshot_url: result.screenshotUrl,
      screenshot_path: result.screenshotPath,
      executed_at: FieldValue.serverTimestamp(),
    })
}

async function completeTestRun(testRunId: string, counts: {
  total: number
  pass: number
  fail: number
}) {
  await db.collection('qa_test_runs').doc(testRunId).update({
    completed_at: FieldValue.serverTimestamp(),
    total_count: counts.total,
    pass_count: counts.pass,
    fail_count: counts.fail,
    status: counts.fail === 0 ? 'pass' : 'fail',
  })
}
```

#### 9.7 Notify — LINE による完了報告

QAエージェントからレポートを受け取った後、PM が LINE Bot（`mcp__line-bot__push_text_message`）でユーザーに報告を送信する。

**QAテストが全て合格した場合** — 報告内容:
- デプロイしたプロジェクト名
- 変更内容の要約
- QAテスト結果（全項目合格、件数）
- 本番環境の確認URL（該当する場合）

**QAテストに失敗した場合** — LINE で失敗内容を報告し、修正対応に入る。自動で修正せず、まずユーザーに状況を通知すること。報告内容:
- 失敗したシナリオの一覧
- 各失敗項目の expected vs actual
- スクリーンショットURL（エビデンス）

### Step 10. Retro — 振り返り（PDCA）

**デプロイ完了後、必ず実施する。** 本番テスト合格を確認した直後に行う。

#### 10.1 プロセスの振り返り

以下の観点でセッション全体を振り返る:

1. **ミスの有無**: 開発フロー・コーディング規約への違反、手戻り、無駄な作業はなかったか
2. **レビュー指摘の分析**: レビューで検出された違反は、実装指示の段階で防げたか
3. **サブエージェントの動作**: worktree隔離は正しく機能したか、並列実行で問題はなかったか
4. **デプロイプロセス**: 手順に問題はなかったか
5. **品質**: 本番テストで想定外の挙動はなかったか
6. **QAテストシナリオ**: テストシナリオは十分だったか、カバレッジに不足はなかったか
7. **エビデンス保存**: Firebase へのスクリーンショット・メタデータ保存に問題はなかったか
8. **品質トレンド**: 過去のテスト結果との比較で劣化（リグレッション）はなかったか

#### 10.2 教訓の記録

振り返りで得た教訓を `tasks/lessons.md` に記録する:

```markdown
## カテゴリ名（日付）
- 教訓1: 具体的に何が起き、今後どうすべきか
- 教訓2: ...
```

#### 10.3 規約・フローの改善

教訓の中で**仕組みで防げるもの**があれば、以下を更新する:

| 問題の種類 | 更新対象 |
|-----------|---------|
| コーディングミスのパターン | `/coding-rules` に禁止パターン追加 |
| デプロイ・本番操作のミス | `/deploy-rules` にルール追加 |
| 開発フローの非効率 | `/develop`（このファイル）のステップ改善 |
| 認証情報・設定の陳腐化 | `memory/MEMORY.md` または該当スキル更新 |
| QAシナリオの不足・漏れ | `qa-scenarios.yml` にシナリオ追加 |

**原則**: 同じミスは2度起こさない。人の注意力に頼らず、ルール・仕組みで防ぐ。

---

## コア原則

- **シンプルさを第一に**: すべての変更を可能な限りシンプルにする。コードへの影響は最小限にする
- **怠惰を許さない**: 根本原因を特定する。一時的な修正は行わない。上級開発者の基準を満たす
- **最小限の影響**: 変更は必要なものだけにとどめ、バグの発生を防ぐ

---

## ワークフロー補則

### デュアルAI意思決定（Claude Code + Codex CLI）

**すべての方針決定・設計判断において、以下のプロセスを標準とする。**

```
Claude Code（主導）        Codex CLI（セカンドオピニオン）
    │                              │
    ├─ 1. 方針・設計を立案          │
    │                              │
    ├─ 2. Codex に意見を求める ────→ 3. 方針を評価・代替案を提示
    │                              │
    ├─ 4. 意見を統合し最終決定 ←────┘
    │
    └─ 5. 確定した方針で実行
```

#### プロセス詳細

1. **Claude Code が方針を立案**: 要件分析、設計案、実装方針を策定する
2. **Codex CLI にセカンドオピニオンを依頼**: 以下のように Bash で呼び出す
   ```bash
   cd <プロジェクトのgitリポジトリルート> && \
   codex exec "
   以下の方針についてセカンドオピニオンをください。
   問題点・リスク・代替案があれば指摘してください。

   ## コンテキスト
   <背景・要件の要約>

   ## 提案方針
   <Claude Code が立案した方針>

   ## 確認したい観点
   - この方針のリスクや盲点はあるか
   - より良い代替アプローチはあるか
   - 見落としている依存関係や影響範囲はないか
   "
   ```
3. **Codex CLI が評価を返す**: 賛同・懸念・代替案を提示
4. **Claude Code が最終決定**: Codex の意見を踏まえ、採用・修正・却下を判断する
   - 賛同 → そのまま実行
   - 有益な指摘 → 方針を修正して実行
   - 意見が分かれた場合 → 理由を明記してユーザーに判断を仰ぐ

#### 適用範囲

| シーン | 必須/推奨 |
|--------|----------|
| 設計・アーキテクチャ判断 | **必須** |
| 複数の実装アプローチがある場合 | **必須** |
| リスクのある変更（DB変更、API変更等） | **必須** |
| 単純な修正・明らかな実装 | 推奨（スキップ可） |
| バグ修正で原因が明確な場合 | スキップ可 |

#### 原則

- **Claude Code が最終意思決定者**。Codex は助言者であり、決定権は Claude Code にある
- Codex の意見を鵜呑みにしない。根拠を評価し、妥当なもののみ採用する
- 意見が対立した場合は両論併記してユーザーに提示する
- セカンドオピニオンの結果（採用/不採用の理由）を tasks/todo.md に記録する

### サブエージェント戦略
- メインコンテキストウィンドウを整理するために、サブエージェントを積極的に使用する
- 調査、探索、並列分析をサブエージェントにオフロードする
- 複雑な問題には、サブエージェントを使ってより多くの計算処理を投入する
- 集中的に実行するために、サブエージェントごとに1つのタスクを割り当てる

### 自己改善ループ（Step 10 と連動）
- **デプロイ後**: Step 10 (Retro) で振り返りを実施し `tasks/lessons.md` を更新する
- **ユーザーからの修正後**: パターンを使用して `tasks/lessons.md` を更新する
- **セッション開始時**: `tasks/lessons.md` を読み、過去の教訓を確認してから作業を開始する
- **仕組み化**: 同じミスを防ぐためのルールをスキルファイルに追加する（人の注意力に頼らない）

### エレガンスを求める（バランス）
- 些細な変更ではない場合：一旦立ち止まり、「もっとエレガントな方法はないか？」と自問する
- 単純で明らかな修正の場合は、この手順を飛ばす – 過剰なエンジニアリングは避けること
- シンプル・イズ・ベストを心がける

### 自律的なバグ修正
- バグレポートを受け取ったら：とにかく修正する。手取り足取り教えてもらう必要はない
- ログ、エラー、失敗したテストを指摘し、それらを解決する
- 指示されなくても、失敗したCIテストを修正できる

### タスク管理
1. **まず計画を立てる**: チェック項目を含む計画を `tasks/todo.md` に記述する
2. **進捗状況を追跡する**: 進捗に合わせて項目を完了としてマークする
3. **変更内容を説明**: 各ステップの概要を示す
4. **教訓を活かす**: 修正後に `tasks/lessons.md` を更新する
